import SwiftUI

struct HomeFeedScrollPreferenceModifier: ViewModifier {
    @ObservedObject var viewModel: HomeViewModel
    @ObservedObject var runtimeSettings: HomeRuntimeSettingsStore
    @Binding var viewportState: HomeFeedViewportState
    let preloadContext: HomeFeedPreloadContext
    let scrollActions: HomeFeedScrollActions
    let preloadActions: HomeFeedPreloadActions
    let refreshActions: HomeFeedRefreshActions

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(HomeFeedWidthPreferenceKey.self, perform: updateFeedContainerWidth)
            .onPreferenceChange(HomeViewportHeightPreferenceKey.self, perform: updateViewportHeight)
            .onPreferenceChange(HomeVisibleVideoFramePreferenceKey.self, perform: updateVisiblePreloadFrames)
            .onPreferenceChange(HomePullRefreshDistancePreferenceKey.self, perform: updatePullRefreshDistance)
    }
}

extension View {
    func homeFeedScrollPreferenceHandling(
        viewModel: HomeViewModel,
        runtimeSettings: HomeRuntimeSettingsStore,
        viewportState: Binding<HomeFeedViewportState>,
        preloadContext: HomeFeedPreloadContext,
        scrollActions: HomeFeedScrollActions,
        preloadActions: HomeFeedPreloadActions,
        refreshActions: HomeFeedRefreshActions
    ) -> some View {
        modifier(
            HomeFeedScrollPreferenceModifier(
                viewModel: viewModel,
                runtimeSettings: runtimeSettings,
                viewportState: viewportState,
                preloadContext: preloadContext,
                scrollActions: scrollActions,
                preloadActions: preloadActions,
                refreshActions: refreshActions
            )
        )
    }
}
