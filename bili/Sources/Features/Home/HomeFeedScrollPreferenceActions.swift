import SwiftUI

extension HomeFeedScrollPreferenceModifier {
    func updateFeedContainerWidth(_ width: CGFloat) {
        viewportState = scrollActions.updateFeedContainerWidth(width, state: viewportState)
    }

    func updateViewportHeight(_ height: CGFloat) {
        viewportState = scrollActions.updateViewportHeight(
            height,
            state: viewportState,
            preloadActions: preloadActions
        )
    }

    func updateVisiblePreloadFrames(_ frames: [HomeVisibleVideoFrame]) {
        scrollActions.updateVisiblePreloadFrames(
            frames,
            context: preloadContext,
            preloadActions: preloadActions
        )
    }

    func updatePullRefreshDistance(_ pullDistance: CGFloat) {
        viewportState = scrollActions.updatePullRefreshDistance(
            pullDistance: pullDistance,
            state: viewportState,
            triggerDistance: CGFloat(runtimeSettings.homeRefreshTriggerDistance),
            isRefreshing: viewModel.isRefreshing,
            refreshActions: refreshActions
        ) {
            await viewModel.refreshFromUserPull()
            return viewModel.state == .loaded
        }
    }
}
