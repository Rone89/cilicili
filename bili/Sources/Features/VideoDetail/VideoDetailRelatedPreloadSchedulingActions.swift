import Foundation

extension VideoDetailViewModel {
    func scheduleRelatedPlaybackPreloadIfAppropriate(for _: [VideoItem]) {
        cancelRelatedPreloadTask()
    }

    func scheduleRelatedPlaybackPreloadAfterFirstFrame(for videos: [VideoItem]) {
        cancelRelatedPreloadTask(advancesGeneration: false)
        let environment = PlaybackEnvironment.current
        let candidateLimit = RelatedPlaybackPrefetchPolicy.candidateLimit(
            environment: environment,
            backgroundPreloadLimit: playbackAdaptationProfile.backgroundPreloadLimit,
            isPlaying: true,
            isBuffering: false
        )
        guard candidateLimit > 0 else {
            cancelRelatedPreloadTask()
            return
        }
        let candidates = Array(videos
            .filter { $0.cid != nil && $0.bvid != detail.bvid }
            .prefix(candidateLimit))
        guard !candidates.isEmpty else {
            cancelRelatedPreloadTask()
            return
        }
        let bvid = detail.bvid
        let preloadGeneration = advanceRelatedPreloadGeneration()
        relatedPreloadTask = Task(priority: .utility) { [weak self, api] in
            guard let self else { return }
            defer {
                self.clearRelatedPreloadTaskIfCurrent(generation: preloadGeneration)
            }
            let didPresentPlayback = await self.waitForFirstFrameOrFailure()
            guard didPresentPlayback,
                  !Task.isCancelled,
                  !self.isPlaybackInvalidatedForNavigation,
                  self.detail.bvid == bvid,
                  self.relatedPreloadGeneration == preloadGeneration
            else { return }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            for (index, video) in candidates.enumerated() {
                guard !Task.isCancelled,
                      !self.isPlaybackInvalidatedForNavigation,
                      self.detail.bvid == bvid,
                      self.relatedPreloadGeneration == preloadGeneration,
                      PlaybackEnvironment.current.networkClass == .wifi,
                      self.stablePlayerViewModel?.isPlaying == true,
                      self.stablePlayerViewModel?.isBuffering == false
                else { return }
                let preferredQuality = self.libraryStore.preferredVideoQuality
                let playbackAdaptationProfile = self.playbackAdaptationProfile
                await VideoPreloadCenter.shared.preloadPlayInfo(
                    video,
                    api: api,
                    preferredQuality: preferredQuality,
                    cdnPreference: self.libraryStore.effectivePlaybackCDNPreference,
                    priority: index == 0 ? .utility : .background,
                    warmsMedia: index == 0,
                    mediaWarmupMode: index == 0 ? .full : .routePlanOnly,
                    mediaWarmupDelay: index == 0 ? 0.15 : 0.4,
                    playbackAdaptationProfile: playbackAdaptationProfile
                )
            }
        }
    }
}
