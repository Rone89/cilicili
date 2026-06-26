import SwiftUI

@MainActor
final class HomeFeedPreloadActions {
    private var coordinator = HomeFeedPreloadCoordinator()

    func beginPressedPreloadIfNeeded(
        for video: VideoItem,
        context: HomeFeedPreloadContext
    ) {
        guard !video.bvid.hasPrefix("av") else { return }
        coordinator.beginPressedPreloadIfNeeded(
            for: video,
            context: context
        )
    }

    func registerVisiblePreloadCandidate(
        _ video: VideoItem,
        index: Int,
        context: HomeFeedPreloadContext
    ) {
        guard !video.bvid.hasPrefix("av") else { return }
        coordinator.registerVisiblePreloadCandidate(
            video,
            index: index,
            context: context
        )
    }

    func updateVisiblePreloadFrames(
        _ frames: [HomeVisibleVideoFrame],
        context: HomeFeedPreloadContext
    ) {
        coordinator.updateVisiblePreloadFrames(
            frames,
            context: context
        )
    }

    func unregisterVisiblePreloadCandidate(_ video: VideoItem) {
        coordinator.unregisterVisiblePreloadCandidate(video)
    }

    func updateViewportHeight(_ height: CGFloat) {
        coordinator.updateViewportHeight(height)
    }
}
