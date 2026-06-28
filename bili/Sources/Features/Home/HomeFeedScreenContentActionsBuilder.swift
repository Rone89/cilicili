import SwiftUI

@MainActor
struct HomeFeedScreenContentActionsBuilder {
    let viewModel: HomeViewModel
    let detailPath: Binding<NavigationPath>
    let launchConfiguration: HomeFeedLaunchConfiguration
    let preloadContext: HomeFeedPreloadContext
    let actionStore: HomeFeedScreenActionStore

    var actions: HomeFeedContentActions {
        HomeFeedContentActions(
            onVideoSelect: launchConfiguration.onVideoSelect,
            onVideoTap: openVideo,
            onVideoPress: beginPressedPreload,
            onVisibleFrame: registerVisiblePreloadCandidate,
            onInvisibleFrame: unregisterVisiblePreloadCandidate,
            onLoadMore: loadMoreIfNeeded
        )
    }

    private func openVideo(_ video: VideoItem) {
        viewModel.recordRecommendClick(video)
        actionStore.card.openVideo(
            video,
            onVideoSelect: launchConfiguration.onVideoSelect,
            detailOpenActions: actionStore.detailOpen,
            appendDetailPath: appendDetailPath
        )
    }

    private func beginPressedPreload(_ video: VideoItem) {
        actionStore.card.beginPressedPreload(
            for: video,
            context: preloadContext,
            preloadActions: actionStore.preload
        )
    }

    private func registerVisiblePreloadCandidate(_ video: VideoItem, index: Int) {
        viewModel.recordRecommendExposure(video, index: index)
        actionStore.card.registerVisiblePreloadCandidate(
            video,
            index: index,
            context: preloadContext,
            preloadActions: actionStore.preload
        )
    }

    private func unregisterVisiblePreloadCandidate(_ video: VideoItem) {
        actionStore.card.unregisterVisiblePreloadCandidate(
            video,
            preloadActions: actionStore.preload
        )
    }

    private func loadMoreIfNeeded(_ video: VideoItem) async {
        await actionStore.card.loadMoreIfNeeded(
            current: video,
            viewModel: viewModel
        )
    }

    private func appendDetailPath(_ video: VideoItem) {
        detailPath.wrappedValue.append(video)
    }
}
