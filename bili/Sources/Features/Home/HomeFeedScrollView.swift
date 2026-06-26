import SwiftUI

struct HomeFeedScrollView<FeedContent: View>: View {
    @ObservedObject var viewModel: HomeViewModel
    @ObservedObject var runtimeSettings: HomeRuntimeSettingsStore
    @Binding var viewportState: HomeFeedViewportState
    let preloadContext: HomeFeedPreloadContext
    let scrollActions: HomeFeedScrollActions
    let preloadActions: HomeFeedPreloadActions
    let refreshActions: HomeFeedRefreshActions
    @ViewBuilder let feedContent: () -> FeedContent

    var body: some View {
        ScrollView {
            HomePullRefreshOffsetReader()
            HomeFeedWidthReader()

            HomeFeedScrollContent(
                isShowingInitialPlaceholder: viewModel.videos.isEmpty && (viewModel.state == .idle || viewModel.state.isLoading),
                isEmpty: viewModel.videos.isEmpty,
                feedContent: feedContent
            )
        }
        .coordinateSpace(name: HomePullRefreshCoordinateSpace.name)
        .rootFloatingTabBarContentPadding()
        .background(HomeViewportHeightReader())
        .homeFeedScrollPreferenceHandling(
            viewModel: viewModel,
            runtimeSettings: runtimeSettings,
            viewportState: $viewportState,
            preloadContext: preloadContext,
            scrollActions: scrollActions,
            preloadActions: preloadActions,
            refreshActions: refreshActions
        )
        .scrollBounceBehavior(.always, axes: .vertical)
        .background(Color.homeAdaptiveBackground)
        .nativeTopScrollEdgeEffect()
        .animation(.smooth(duration: 0.24), value: runtimeSettings.homeFeedLayout)
        .homeFeedScrollOverlays(
            viewModel: viewModel,
            runtimeSettings: runtimeSettings,
            viewportState: viewportState,
            refreshActions: refreshActions
        )
    }
}
