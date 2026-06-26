import Foundation

extension HomeFeedMediaPreloadCoordinator {
    func schedulePlaybackPreload(for videos: [VideoItem], initialDelay: TimeInterval) {
        playbackPreloadTask?.cancel()
        let playbackAdaptationProfile = PlayerPerformanceStore.shared.playbackAdaptationProfile(
            isEnabled: libraryStore.isPlaybackAutoOptimizationEnabled
        )
        let candidateLimit = max(0, min(1, playbackAdaptationProfile.backgroundRoutePlanPreloadLimit))
        guard candidateLimit > 0 else {
            playbackPreloadTask = nil
            return
        }
        let candidates = Array(videos
            .filter { $0.cid != nil && !$0.bvid.isEmpty && !$0.bvid.hasPrefix("av") }
            .prefix(candidateLimit))
        guard !candidates.isEmpty else {
            playbackPreloadTask = nil
            return
        }

        let preferredQuality = libraryStore.preferredVideoQuality
        let cdnPreference = libraryStore.effectivePlaybackCDNPreference
        playbackPreloadTask = Task(priority: .utility) { [api, cdnPreference] in
            let startupDelay = max(0.12, min(initialDelay, 0.35))
            try? await Task.sleep(nanoseconds: UInt64(startupDelay * 1_000_000_000))
            for (index, video) in candidates.enumerated() {
                guard !Task.isCancelled else { return }
                await VideoPreloadCenter.shared.updatePlaybackPreferences(
                    preferredQuality: preferredQuality,
                    cdnPreference: cdnPreference,
                    playbackAdaptationProfile: playbackAdaptationProfile
                )
                await VideoPreloadCenter.shared.preloadPlayInfo(
                    video,
                    api: api,
                    preferredQuality: preferredQuality,
                    cdnPreference: cdnPreference,
                    priority: .utility,
                    warmsMedia: true,
                    mediaWarmupMode: .full,
                    mediaWarmupDelay: 0.08,
                    playbackAdaptationProfile: playbackAdaptationProfile
                )
                if index < candidates.count - 1 {
                    try? await Task.sleep(nanoseconds: 650_000_000)
                }
            }
        }
    }
}
