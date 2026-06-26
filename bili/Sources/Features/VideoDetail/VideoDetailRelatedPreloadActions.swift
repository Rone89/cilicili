import SwiftUI

@MainActor
struct VideoDetailRelatedPreloadActions {
    @Binding var preloadedVideoIDs: Set<String>
    let api: BiliAPIClient
    let runtimeSettings: VideoDetailRuntimeSettingsSnapshot

    func beginPreloadIfNeeded(_ video: VideoItem) {
        guard !video.bvid.isEmpty,
              !preloadedVideoIDs.contains(video.bvid),
              preloadedVideoIDs.count < 1,
              !PlaybackEnvironment.current.shouldPreferConservativePlayback
        else { return }

        let playbackAdaptationProfile = PlayerPerformanceStore.shared.playbackAdaptationProfile(
            isEnabled: runtimeSettings.playbackAutoOptimizationEnabled
        )
        guard playbackAdaptationProfile.backgroundPreloadLimit > 1 else { return }

        preloadedVideoIDs.insert(video.bvid)
        Task(priority: .utility) {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            await VideoPreloadCenter.shared.preloadPlayInfo(
                video,
                api: api,
                preferredQuality: runtimeSettings.preferredVideoQuality,
                cdnPreference: runtimeSettings.effectivePlaybackCDNPreference,
                priority: .utility,
                warmsMedia: true,
                mediaWarmupMode: .full,
                mediaWarmupDelay: 0.05,
                playbackAdaptationProfile: playbackAdaptationProfile
            )
        }
    }
}
