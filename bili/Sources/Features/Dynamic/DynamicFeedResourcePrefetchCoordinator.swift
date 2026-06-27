import Foundation

@MainActor
final class DynamicFeedResourcePrefetchCoordinator {
    private let api: BiliAPIClient
    private let libraryStore: LibraryStore
    private var imagePrefetchTask: Task<Void, Never>?
    private var playbackPreloadTask: Task<Void, Never>?
    private let resourcePrefetchDebouncer = TaskDebouncer()

    init(api: BiliAPIClient, libraryStore: LibraryStore) {
        self.api = api
        self.libraryStore = libraryStore
    }

    deinit {
        imagePrefetchTask?.cancel()
        playbackPreloadTask?.cancel()
    }

    func scheduleResourcePrefetch(for items: [DynamicFeedItem], initialDelay: TimeInterval) {
        let environment = PlaybackEnvironment.current
        let snapshotLimit = environment.shouldPreferConservativePlayback ? 5 : 8
        let snapshot = Array(items.prefix(snapshotLimit))
        let adaptiveDelay = environment.shouldPreferConservativePlayback ? initialDelay + 0.45 : initialDelay + 0.2
        let delayMilliseconds = max(Int64((adaptiveDelay * 1000).rounded()), 120)
        resourcePrefetchDebouncer.schedule(delay: .milliseconds(delayMilliseconds)) { [weak self] in
            guard let self else { return }
            self.scheduleImagePrefetch(for: snapshot, initialDelay: 0)
            guard !environment.shouldPreferConservativePlayback else { return }
            self.schedulePlaybackPreload(for: snapshot, initialDelay: 0.45)
        }
    }

    private func scheduleImagePrefetch(for items: [DynamicFeedItem], initialDelay: TimeInterval) {
        imagePrefetchTask?.cancel()
        let environment = PlaybackEnvironment.current
        let prefetchPlan = dynamicImagePrefetchPlan(for: items, environment: environment)

        guard !prefetchPlan.avatarSources.isEmpty || !prefetchPlan.imageSources.isEmpty || !prefetchPlan.coverSources.isEmpty else { return }
        let avatarPrefetchSources = prefetchPlan.avatarSources
        let imagePrefetchSources = prefetchPlan.imageSources
        let coverPrefetchSources = prefetchPlan.coverSources
        let imageTargetPixelSize = environment.shouldPreferConservativePlayback ? 320 : 420
        let coverTargetPixelSize = environment.shouldPreferConservativePlayback ? 360 : 480
        imagePrefetchTask = Task(priority: .utility) {
            if initialDelay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(initialDelay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            async let avatars: Void = RemoteImageCache.shared.prefetch(
                avatarPrefetchSources,
                targetPixelSize: 96,
                maximumConcurrentLoads: 1
            )
            async let images: Void = RemoteImageCache.shared.prefetch(
                imagePrefetchSources,
                targetPixelSize: imageTargetPixelSize,
                maximumConcurrentLoads: environment.shouldPreferConservativePlayback ? 1 : 2
            )
            async let covers: Void = RemoteImageCache.shared.prefetch(
                coverPrefetchSources,
                targetPixelSize: coverTargetPixelSize,
                maximumConcurrentLoads: 1
            )
            _ = await (avatars, images, covers)
        }
    }

    private func dynamicImagePrefetchPlan(
        for items: [DynamicFeedItem],
        environment: PlaybackEnvironment
    ) -> (avatarSources: [RemoteImageSource], imageSources: [RemoteImageSource], coverSources: [RemoteImageSource]) {
        var avatarSources = [RemoteImageSource]()
        var imageSources = [RemoteImageSource]()
        var coverSources = [RemoteImageSource]()
        var seenURLs = Set<String>()

        let itemLimit = environment.shouldPreferConservativePlayback ? 5 : 8
        let imageLimit = environment.shouldPreferConservativePlayback ? 2 : 3
        let imageTargetPixelSize = environment.shouldPreferConservativePlayback ? 320 : 420
        let coverTargetPixelSize = environment.shouldPreferConservativePlayback ? 360 : 480
        for item in items.prefix(itemLimit) {
            if let source = item.author?.face?.normalizedBiliURL(),
               let avatarURL = URL(string: source.biliAvatarThumbnailURL(size: 96)),
               seenURLs.insert(source).inserted {
                avatarSources.append(RemoteImageSource(url: avatarURL, fallbackURL: URL(string: source)))
            }

            for image in item.imageItems.prefix(imageLimit) {
                guard let source = image.normalizedURL,
                      let url = URL(string: source.biliImageThumbnailURL(maxSide: imageTargetPixelSize)),
                      seenURLs.insert(source).inserted
                else { continue }
                imageSources.append(RemoteImageSource(url: url, fallbackURL: URL(string: source)))
            }

            if let video = item.archive?.asVideoItem(author: item.author),
               let source = video.pic?.normalizedBiliURL(),
               let coverURL = URL(string: source.biliCoverThumbnailURL(width: coverTargetPixelSize, height: Int(Double(coverTargetPixelSize) * 9 / 16))),
               seenURLs.insert(source).inserted {
                coverSources.append(RemoteImageSource(url: coverURL, fallbackURL: URL(string: source)))
            }

            if let source = item.paidContent?.normalizedCoverURL,
               let coverURL = URL(string: source.biliCoverThumbnailURL(width: coverTargetPixelSize, height: Int(Double(coverTargetPixelSize) * 9 / 16))),
               seenURLs.insert(source).inserted {
                coverSources.append(RemoteImageSource(url: coverURL, fallbackURL: URL(string: source)))
            }
        }

        return (avatarSources, imageSources, coverSources)
    }

    private func schedulePlaybackPreload(for items: [DynamicFeedItem], initialDelay: TimeInterval) {
        playbackPreloadTask?.cancel()
        guard !PlaybackEnvironment.current.shouldPreferConservativePlayback else {
            playbackPreloadTask = nil
            return
        }

        let videos = items
            .compactMap { $0.archive?.asVideoItem(author: $0.author) }
            .filter { !$0.bvid.isEmpty }
        let playbackAdaptationProfile = PlayerPerformanceStore.shared.playbackAdaptationProfile(
            isEnabled: libraryStore.isPlaybackAutoOptimizationEnabled
        )
        let candidateLimit = max(0, min(2, playbackAdaptationProfile.backgroundPreloadLimit))
        guard candidateLimit > 0 else {
            playbackPreloadTask = nil
            return
        }
        let candidates = Array(videos.prefix(candidateLimit))
        guard !candidates.isEmpty else {
            playbackPreloadTask = nil
            return
        }

        let preferredQuality = libraryStore.preferredVideoQuality
        let cdnPreference = libraryStore.effectivePlaybackCDNPreference
        playbackPreloadTask = Task(priority: .background) { [api, cdnPreference] in
            if initialDelay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(initialDelay * 1_000_000_000))
            }
            await VideoPreloadCenter.shared.updatePlaybackPreferences(
                preferredQuality: preferredQuality,
                cdnPreference: cdnPreference,
                playbackAdaptationProfile: playbackAdaptationProfile
            )
            for (index, video) in candidates.enumerated() {
                guard !Task.isCancelled else { return }
                let isPrimary = index == 0
                await VideoPreloadCenter.shared.preloadPlayInfo(
                    video,
                    api: api,
                    preferredQuality: preferredQuality,
                    cdnPreference: cdnPreference,
                    priority: .background,
                    warmsMedia: true,
                    mediaWarmupMode: isPrimary ? .full : .routePlanOnly,
                    mediaWarmupDelay: isPrimary ? 0.45 : 0.65,
                    playbackAdaptationProfile: playbackAdaptationProfile
                )
                if index < candidates.count - 1 {
                    try? await Task.sleep(nanoseconds: 650_000_000)
                }
            }
        }
    }
}
