import SwiftUI

extension RootTabView {
    var shouldAutoOpenDetail: Bool {
        !didConsumeStartupVideo && shouldStartDetail && startBVID == nil
    }

    func openStartupVideoIfNeeded() {
        guard !didConsumeStartupVideo,
              let startBVID
        else { return }

        openVideo(Self.seedVideo(bvid: startBVID))
    }

    func openStartupLiveRoomIfNeeded() {
        guard !didConsumeStartupLiveRoom,
              let startLiveRoomID
        else { return }

        didConsumeStartupLiveRoom = true
        selectedTab = .live
        DispatchQueue.main.async {
            liveNavigationPath.append(Self.seedLiveRoom(roomID: startLiveRoomID))
        }
    }

    func openAppURL(_ url: URL) {
        guard AppLinkRouter.canHandle(url) else { return }

        Task { @MainActor in
            let destination = await AppLinkRouter.destination(for: url, api: dependencies.api)
            routeAppLinkDestination(destination)
        }
    }

    func routeAppLinkDestination(_ destination: AppLinkDestination) {
        switch destination {
        case .video(let video):
            openVideo(video)
        case .liveRoom(let room):
            openLiveRoomFromLink(room)
        case .user(let owner):
            openUserFromLink(owner)
        case .browser(let url):
            inAppBrowserItem = InAppBrowserItem(url: url)
        }
    }

    func openLiveRoomFromLink(_ room: LiveRoom) {
        AppOrientationLock.restorePortrait()
        if bottomMode == .video {
            ActivePlaybackCoordinator.shared.stopActivePlayback()
            NotificationCenter.default.post(name: .biliStopActiveVideoPlayback, object: nil)
            withAnimation(.smooth(duration: 0.28)) {
                videoNavigationPath.append(room)
            }
            return
        }

        selectedTab = .live
        DispatchQueue.main.async {
            liveNavigationPath.append(room)
        }
    }

    func openUserFromLink(_ owner: VideoOwner) {
        AppOrientationLock.restorePortrait()
        if bottomMode == .video {
            withAnimation(.smooth(duration: 0.28)) {
                videoNavigationPath.append(owner)
            }
            return
        }

        DispatchQueue.main.async {
            switch selectedTab {
            case .home:
                navigationPath.append(owner)
            case .dynamic:
                dynamicNavigationPath.append(owner)
            case .live:
                liveNavigationPath.append(owner)
            case .mine:
                mineNavigationPath.append(owner)
            case .search:
                searchNavigationPath.append(owner)
            }
        }
    }

    func videoNavigationHost() -> some View {
        RootVideoNavigationHost(
            path: $videoNavigationPath,
            isClosingVideo: isClosingVideo,
            onRequestClose: closeVideo,
            onCancelledClose: cancelCloseVideoIfNeeded,
            onCompletedClose: completeCloseVideoIfNeeded
        ) {
            guard bottomMode == .video else { return }
            scheduleCloseVideo()
        }
    }

    func openVideo(_ video: VideoItem) {
        AppOrientationLock.restorePortrait()
        PlayerMetricsLog.record(.routeOpen, metricsID: video.bvid, title: video.title)
        if bottomMode == .video {
            pushVideo(video)
            return
        }

        beginPlaybackPreload(for: video)
        let update = {
            videoPresentationGeneration &+= 1
            didConsumeStartupVideo = true
            isClosingVideo = false
            activeVideo = video
            videoNavigationPath = NavigationPath()
            bottomMode = .video
        }

        let opensFromStartup = shouldStartDetail && !didConsumeStartupVideo
        if shouldStartDetail && !didConsumeStartupVideo {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction, update)
        } else {
            withAnimation(.smooth(duration: 0.32), update)
        }
        pushInitialVideo(video, generation: videoPresentationGeneration, animated: !opensFromStartup)
    }

    func pushVideo(_ video: VideoItem) {
        AppOrientationLock.restorePortrait()
        PlayerMetricsLog.record(.routeOpen, metricsID: video.bvid, title: video.title)
        ActivePlaybackCoordinator.shared.pauseActivePlaybackForNavigation()
        NotificationCenter.default.post(name: .biliPauseActiveVideoPlaybackForNavigation, object: nil)
        beginPlaybackPreload(for: video)
        withAnimation(.smooth(duration: 0.28)) {
            didConsumeStartupVideo = true
            isClosingVideo = false
            videoNavigationPath.append(video)
        }
    }

    func beginPlaybackPreload(for video: VideoItem) {
        guard !video.bvid.isEmpty, !video.bvid.hasPrefix("av") else { return }
        let now = Date()
        if let lastPreload = recentPlaybackPreloadTimes[video.bvid],
           now.timeIntervalSince(lastPreload) < 1.2 {
            return
        }
        recentPlaybackPreloadTimes[video.bvid] = now
        trimRecentPlaybackPreloads(now: now)

        Task {
            dependencies.refreshPlaybackCDNProbeIfNeeded()
            let playbackAdaptationProfile = PlayerPerformanceStore.shared.playbackAdaptationProfile(
                for: video.bvid,
                isEnabled: dependencies.libraryStore.isPlaybackAutoOptimizationEnabled
            )
            let preferredQuality = dependencies.libraryStore.preferredVideoQuality
            let cdnPreference = dependencies.libraryStore.effectivePlaybackCDNPreference
            let api = dependencies.api
            await VideoPreloadCenter.shared.updatePlaybackPreferences(
                preferredQuality: preferredQuality,
                cdnPreference: cdnPreference,
                playbackAdaptationProfile: playbackAdaptationProfile
            )
            await VideoPreloadCenter.shared.prioritizePlayback(for: video)
            await VideoPreloadCenter.shared.preloadPlayInfo(
                video,
                api: api,
                preferredQuality: preferredQuality,
                cdnPreference: cdnPreference,
                priority: .userInitiated,
                warmsMedia: true,
                mediaWarmupDelay: 0,
                playbackAdaptationProfile: playbackAdaptationProfile
            )
        }
    }

    func trimRecentPlaybackPreloads(now: Date) {
        recentPlaybackPreloadTimes = recentPlaybackPreloadTimes.filter { _, date in
            now.timeIntervalSince(date) < 8
        }
        guard recentPlaybackPreloadTimes.count > 16 else { return }
        let keptKeys = Set(
            recentPlaybackPreloadTimes
                .sorted { $0.value > $1.value }
                .prefix(16)
                .map(\.key)
        )
        recentPlaybackPreloadTimes = recentPlaybackPreloadTimes.filter { keptKeys.contains($0.key) }
    }

    func pushInitialVideo(_ video: VideoItem, generation: Int, animated: Bool) {
        DispatchQueue.main.async {
            guard bottomMode == .video,
                  videoNavigationPath.isEmpty,
                  activeVideo?.id == video.id,
                  videoPresentationGeneration == generation,
                  !isClosingVideo
            else { return }

            let push = {
                videoNavigationPath.append(video)
            }

            if animated {
                withAnimation(.smooth(duration: 0.30), push)
            } else {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction, push)
            }
        }
    }

    func restoreVideoPlaybackUIForPictureInPicture(_ video: VideoItem) async -> Bool {
        closeVideoFallbackTask?.cancel()
        closeVideoFallbackTask = nil
        AppOrientationLock.restorePortrait()

        let isAlreadyShowingPlaybackPage = bottomMode == .video
            && !isClosingVideo
            && activeVideo?.id == video.id
            && videoNavigationPath.count == 1
        guard !isAlreadyShowingPlaybackPage else { return true }

        beginPlaybackPreload(for: video)
        videoPresentationGeneration &+= 1
        didConsumeStartupVideo = true
        isClosingVideo = false

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            activeVideo = video
            videoNavigationPath = NavigationPath()
            bottomMode = .video
        }

        await Task.yield()
        guard bottomMode == .video,
              activeVideo?.id == video.id,
              !isClosingVideo
        else { return false }

        videoNavigationPath.append(video)
        await Task.yield()
        return bottomMode == .video && !videoNavigationPath.isEmpty
    }

    func closeVideo() {
        guard bottomMode == .video else { return }
        beginDefinitiveVideoClose()
    }

    func scheduleCloseVideo() {
        guard bottomMode == .video, !isClosingVideo else {
            return
        }
        isClosingVideo = true
        videoPresentationGeneration &+= 1
        ActivePlaybackCoordinator.shared.pauseActivePlaybackForNavigation()
        NotificationCenter.default.post(name: .biliPauseActiveVideoPlaybackForNavigation, object: nil)
        closeVideoFallbackTask?.cancel()
        closeVideoFallbackTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 850_000_000)
            guard !Task.isCancelled, bottomMode == .video, isClosingVideo else { return }
            completeCloseVideoIfNeeded()
        }
    }

    func beginDefinitiveVideoClose() {
        isClosingVideo = true
        videoPresentationGeneration &+= 1
        closeVideoFallbackTask?.cancel()
        closeVideoFallbackTask = nil
        ActivePlaybackCoordinator.shared.stopActivePlayback()
        NotificationCenter.default.post(name: .biliStopActiveVideoPlayback, object: nil)
        AppOrientationLock.restorePortrait()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            activeVideo = nil
            videoNavigationPath = NavigationPath()
            bottomMode = .root
            isClosingVideo = false
        }
        rootTabBarRestoreRequestID &+= 1
    }

    func cancelCloseVideoIfNeeded() {
        guard bottomMode == .video, isClosingVideo else { return }
        closeVideoFallbackTask?.cancel()
        closeVideoFallbackTask = nil
        isClosingVideo = false
        NotificationCenter.default.post(name: .biliResumeActiveVideoPlaybackAfterCancelledNavigation, object: nil)
    }

    func completeCloseVideoIfNeeded() {
        guard bottomMode == .video, isClosingVideo else { return }
        closeVideoFallbackTask?.cancel()
        closeVideoFallbackTask = nil
        ActivePlaybackCoordinator.shared.stopActivePlayback()
        NotificationCenter.default.post(name: .biliStopActiveVideoPlayback, object: nil)
        AppOrientationLock.restorePortrait()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            activeVideo = nil
            videoNavigationPath = NavigationPath()
            bottomMode = .root
            isClosingVideo = false
        }
        rootTabBarRestoreRequestID &+= 1
    }
}
