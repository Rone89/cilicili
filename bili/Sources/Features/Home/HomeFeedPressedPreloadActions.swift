import SwiftUI

extension HomeFeedPreloadCoordinator {
    func beginPressedPreloadIfNeeded(
        for video: VideoItem,
        context: HomeFeedPreloadContext
    ) {
        let bvid = video.bvid
        guard !bvid.isEmpty, !pressedPreloadVideos.contains(bvid) else { return }
        pressedPreloadVideos.insert(bvid)

        Task {
            await VideoPreloadCenter.shared.updatePlaybackPreferences(
                preferredQuality: context.preferredQuality,
                cdnPreference: context.cdnPreference,
                playbackAdaptationProfile: context.playbackAdaptationProfile
            )
            await VideoPreloadCenter.shared.prioritizePlayback(for: video)
            await VideoPreloadCenter.shared.preloadPlayInfo(
                video,
                api: context.api,
                preferredQuality: context.preferredQuality,
                cdnPreference: context.cdnPreference,
                priority: .userInitiated,
                warmsMedia: true,
                mediaWarmupDelay: 0,
                playbackAdaptationProfile: context.playbackAdaptationProfile
            )
        }
    }
}
