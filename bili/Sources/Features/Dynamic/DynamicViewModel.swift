import Combine
import Foundation
#if DEBUG
import OSLog
#endif

#if DEBUG
private let dynamicDiagnosticsLogger = Logger(subsystem: "cc.bili", category: "DynamicDiagnostics")
#endif

@MainActor
final class DynamicViewModel: ObservableObject {
    @Published var items: [DynamicFeedItem] = [] {
        didSet {
            itemsRevision &+= 1
        }
    }
    @Published private(set) var followedLiveRooms: [LiveRoom] = [] {
        didSet {
            followedLiveRoomsRevision &+= 1
        }
    }
    @Published var state: LoadingState = .idle
    @Published private(set) var itemsRevision = 0
    @Published private(set) var followedLiveRoomsRevision = 0

    private let api: BiliAPIClient
    private let libraryStore: LibraryStore
    private let sessionStore: SessionStore
    private var rawItems: [DynamicFeedItem] = []
    private var offset = ""
    private var hasMore = true
    private var filterCancellable: AnyCancellable?
    private var imagePrefetchTask: Task<Void, Never>?
    private var playbackPreloadTask: Task<Void, Never>?
    private var followedLiveTask: Task<Void, Never>?
    private let resourcePrefetchDebouncer = TaskDebouncer()

    var hasMoreItems: Bool {
        hasMore
    }

    init(api: BiliAPIClient, libraryStore: LibraryStore, sessionStore: SessionStore) {
        self.api = api
        self.libraryStore = libraryStore
        self.sessionStore = sessionStore
        filterCancellable = libraryStore.$blocksAdDynamics
            .combineLatest(libraryStore.$blocksGoodsDynamics)
            .combineLatest(libraryStore.$blockedDynamicKeywords)
            .removeDuplicates { lhs, rhs in
                lhs.0.0 == rhs.0.0
                    && lhs.0.1 == rhs.0.1
                    && lhs.1 == rhs.1
            }
            .dropFirst()
            .sink { [weak self] _ in
                self?.applyCurrentFilter()
            }
    }

    deinit {
        imagePrefetchTask?.cancel()
        playbackPreloadTask?.cancel()
        followedLiveTask?.cancel()
    }

    func loadInitial() async {
        guard items.isEmpty else { return }
        guard sessionStore.isLoggedIn else {
            prepareLoggedOutState()
            return
        }
        state = .loading
        offset = ""
        hasMore = true
        refreshFollowedLiveRooms()
        do {
            let page = try await DynamicFeedWarmCache.shared.page(api: api)
            apply(page: page, prefetchDelay: 0.08)
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func refresh() async {
        guard sessionStore.isLoggedIn else {
            prepareLoggedOutState()
            return
        }
        state = .loading
        offset = ""
        hasMore = true
        refreshFollowedLiveRooms()
        do {
            let page = try await api.fetchDynamicFeed()
            await DynamicFeedWarmCache.shared.store(page)
            apply(page: page, prefetchDelay: 0.08)
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func loadMoreIfNeeded(current item: DynamicFeedItem?) async {
        guard let item, items.last?.id == item.id else { return }
        await loadMore()
    }

    func loadMore() async {
        guard sessionStore.isLoggedIn else {
            prepareLoggedOutState()
            return
        }
        guard hasMore, !state.isLoading else { return }
        state = .loading
        do {
            let page = try await api.fetchDynamicFeed(offset: offset)
            let moreItems = displayable(page.items)
            appendUniqueRaw(moreItems)
            applyCurrentFilter()
            scheduleResourcePrefetch(for: moreItems, initialDelay: 0.75)
            offset = page.offset ?? offset
            hasMore = page.hasMore ?? false
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func prepareLoggedOutState() {
        followedLiveTask?.cancel()
        followedLiveTask = nil
        rawItems = []
        items = []
        followedLiveRooms = []
        offset = ""
        hasMore = false
        state = .idle
    }

    private func apply(page: DynamicFeedData, prefetchDelay: TimeInterval) {
        rawItems = displayable(page.items)
        applyCurrentFilter()
        scheduleResourcePrefetch(for: items, initialDelay: prefetchDelay)
        offset = page.offset ?? ""
        hasMore = page.hasMore ?? false
    }

    private func displayable(_ items: [DynamicFeedItem]?) -> [DynamicFeedItem] {
        (items ?? []).filter { item in
            let isDisplayable = item.displayText?.isEmpty == false
                || item.archive != nil
                || item.live != nil
                || item.paidContent != nil
                || !item.imageItems.isEmpty
                || item.original?.hasDisplayableContent == true
#if DEBUG
            if !isDisplayable, item.author != nil {
                dynamicDiagnosticsLogger.debug("Dropped empty dynamic: \(item.contentDiagnosticSummary, privacy: .public)")
            }
#endif
            return isDisplayable
        }
    }

    private func applyCurrentFilter() {
        var filteredItems = rawItems
        if libraryStore.blocksAdDynamics {
            filteredItems = filteredItems.filter { !$0.containsDynamicAdPromotion }
        }
        if libraryStore.blocksGoodsDynamics {
            filteredItems = filteredItems.filter { !$0.containsGoodsPromotion }
        }
        let blockedKeywords = libraryStore.blockedDynamicKeywords
        if !blockedKeywords.isEmpty {
            filteredItems = filteredItems.filter { !$0.matchesBlockedDynamicKeywords(blockedKeywords) }
        }
        items = filteredItems
    }

    private func appendUniqueRaw(_ more: [DynamicFeedItem]) {
        let existing = Set(rawItems.map(\.id))
        rawItems.append(contentsOf: more.filter { !existing.contains($0.id) })
    }

    private func refreshFollowedLiveRooms() {
        followedLiveTask?.cancel()
        followedLiveTask = Task { [weak self, api] in
            do {
                let rooms = try await api.fetchFollowedLiveRooms(page: 1, pageSize: 20)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.followedLiveRooms = Array(rooms.prefix(12))
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.followedLiveRooms = []
                }
            }
        }
    }

    private func scheduleResourcePrefetch(for items: [DynamicFeedItem], initialDelay: TimeInterval) {
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
                await VideoPreloadCenter.shared.preloadPlayInfo(
                    video,
                    api: api,
                    preferredQuality: preferredQuality,
                    cdnPreference: cdnPreference,
                    priority: .background,
                    warmsMedia: true,
                    mediaWarmupDelay: index == 0 ? 0.45 : 0.9,
                    playbackAdaptationProfile: playbackAdaptationProfile
                )
                if index < candidates.count - 1 {
                    try? await Task.sleep(nanoseconds: 650_000_000)
                }
            }
        }
    }
}
