import SwiftUI

extension HomeFeedPreloadCoordinator {
    func beginVisiblePreloadIfNeeded(
        for video: VideoItem,
        context: HomeFeedPreloadContext,
        isPrimary: Bool = true
    ) {
        let bvid = video.bvid
        guard visiblePreloadRegistry.canBeginPreload(
            for: bvid,
            routePlanPreloadLimit: context.playbackAdaptationProfile.backgroundRoutePlanPreloadLimit
        ) else { return }

        visiblePreloadRegistry.markPreloadStarted(for: bvid)
        let mediaWarmupMode: VideoPreloadMediaWarmupMode = isPrimary ? .full : .routePlanOnly
        let mediaWarmupDelay: TimeInterval = isPrimary ? 0.05 : 0.25
        Task(priority: .utility) {
            await VideoPreloadCenter.shared.preloadPlayInfo(
                video,
                api: context.api,
                preferredQuality: context.preferredQuality,
                cdnPreference: context.cdnPreference,
                priority: .utility,
                warmsMedia: true,
                mediaWarmupMode: mediaWarmupMode,
                mediaWarmupDelay: mediaWarmupDelay,
                playbackAdaptationProfile: context.playbackAdaptationProfile
            )
        }
    }
}
