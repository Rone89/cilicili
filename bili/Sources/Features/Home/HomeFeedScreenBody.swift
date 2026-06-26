import SwiftUI

struct HomeFeedScreenBody: View {
    @ObservedObject var viewModel: HomeViewModel
    @ObservedObject var runtimeSettings: HomeRuntimeSettingsStore
    @ObservedObject var libraryStore: LibraryStore
    @Binding var viewportState: HomeFeedViewportState
    @Binding var detailPath: NavigationPath
    let preloadContext: HomeFeedPreloadContext
    let contentActions: HomeFeedContentActions
    let actionStore: HomeFeedScreenActionStore
    let launchConfiguration: HomeFeedLaunchConfiguration

    var body: some View {
        HomeFeedScrollView(
            viewModel: viewModel,
            runtimeSettings: runtimeSettings,
            viewportState: $viewportState,
            preloadContext: preloadContext,
            scrollActions: actionStore.scroll,
            preloadActions: actionStore.preload,
            refreshActions: actionStore.refresh
        ) {
            HomeFeedContentSection(
                metrics: viewportState.layoutMetrics(for: runtimeSettings.homeFeedLayout),
                cells: viewModel.videoCells,
                isLoadingMore: viewModel.state.isLoading && !viewModel.isRefreshing,
                actions: contentActions
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.homeAdaptiveBackground)
        .homeFeedScreenLifecycle(
            viewModel: viewModel,
            runtimeSettings: runtimeSettings,
            libraryStore: libraryStore,
            detailPath: $detailPath,
            configuration: lifecycleConfiguration
        )
    }

    private var lifecycleConfiguration: HomeFeedScreenLifecycleConfiguration {
        HomeFeedScreenLifecycleConfiguration(
            launchConfiguration: launchConfiguration,
            lifecycleActions: actionStore.lifecycle,
            detailOpenActions: actionStore.detailOpen
        )
    }
}
