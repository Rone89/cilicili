import SwiftUI

struct HomeFeedScreenContent: View {
    @EnvironmentObject var dependencies: AppDependencies
    @StateObject var runtimeSettings = HomeRuntimeSettingsStore()
    @ObservedObject var viewModel: HomeViewModel
    @Binding var detailPath: NavigationPath
    let launchConfiguration: HomeFeedLaunchConfiguration
    @State var viewportState = HomeFeedViewportState()
    @State var actionStore = HomeFeedScreenActionStore()

    init(
        viewModel: HomeViewModel,
        detailPath: Binding<NavigationPath>,
        launchConfiguration: HomeFeedLaunchConfiguration
    ) {
        self.viewModel = viewModel
        _detailPath = detailPath
        self.launchConfiguration = launchConfiguration
    }

    var body: some View {
        let renderPack = renderPack

        HomeFeedScreenBody(
            viewModel: viewModel,
            runtimeSettings: runtimeSettings,
            libraryStore: dependencies.libraryStore,
            viewportState: $viewportState,
            detailPath: $detailPath,
            preloadContext: renderPack.preloadContext,
            contentActions: renderPack.contentActions,
            actionStore: actionStore,
            launchConfiguration: launchConfiguration
        )
        .homeFeedNavigationChrome(
            viewModel: viewModel,
            modeActions: actionStore.mode
        )
    }
}
