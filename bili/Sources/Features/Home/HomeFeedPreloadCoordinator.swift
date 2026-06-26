import SwiftUI
import OSLog

@MainActor
final class HomeFeedPreloadCoordinator {
    var pressedPreloadVideos = Set<String>()
    var visiblePreloadRegistry = HomeVisiblePreloadRegistry()
    let visiblePreloadDebouncer = TaskDebouncer()

    func registerVisiblePreloadCandidate(
        _ video: VideoItem,
        index: Int,
        context: HomeFeedPreloadContext
    ) {
        guard !video.bvid.isEmpty else { return }
        visiblePreloadRegistry.register(video, index: index)
        scheduleVisiblePreload(
            delay: .milliseconds(220),
            context: context
        )
    }

    func updateVisiblePreloadFrames(
        _ frames: [HomeVisibleVideoFrame],
        context: HomeFeedPreloadContext
    ) {
        guard !frames.isEmpty else { return }
        guard visiblePreloadRegistry.updateFrames(frames) else { return }
        scheduleVisiblePreload(
            delay: .milliseconds(90),
            context: context
        )
    }

    func unregisterVisiblePreloadCandidate(_ video: VideoItem) {
        if visiblePreloadRegistry.unregister(video) {
            visiblePreloadDebouncer.cancel()
        }
    }

    func updateViewportHeight(_ height: CGFloat) {
        visiblePreloadRegistry.updateViewportHeight(height)
    }

}
