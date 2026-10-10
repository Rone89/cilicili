import SwiftUI

struct HomeFeedScreenContent: View {
    @EnvironmentObject var dependencies: AppDependencies
    @StateObject var runtimeSettings = HomeRuntimeSettingsStore()
    @ObservedObject var viewModel: HomeViewModel
    @Binding var detailPath: NavigationPath
    let actionStore: HomeFeedScreenActionStore
    let launchConfiguration: HomeFeedLaunchConfiguration
    @State var viewportState = HomeFeedViewportState()

    init(
        viewModel: HomeViewModel,
        detailPath: Binding<NavigationPath>,
        actionStore: HomeFeedScreenActionStore,
        launchConfiguration: HomeFeedLaunchConfiguration
    ) {
        self.viewModel = viewModel
        _detailPath = detailPath
        self.actionStore = actionStore
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
            contentActions: renderPack.contentActions,
            actionStore: actionStore,
            launchConfiguration: launchConfiguration
        )
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            StageOneBaselineMetricsStore.shared.markHomeFirstInteractive()
        }
    }
}
