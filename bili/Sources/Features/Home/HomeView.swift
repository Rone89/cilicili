import SwiftUI

struct HomeView: View {
    let launchConfiguration: HomeFeedLaunchConfiguration
    let actionStore: HomeFeedScreenActionStore
    @ObservedObject private var viewModel: HomeViewModel
    @Binding var detailPath: NavigationPath
    @StateObject private var titleState = FeedChromeTitleState()

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
        HomeFeedScreenContent(
            viewModel: viewModel,
            detailPath: $detailPath,
            actionStore: actionStore,
            launchConfiguration: launchConfiguration
        )
        .environment(\.feedChromeTitleState, titleState)
        .safeAreaInset(edge: .top, spacing: 12) {
            HomeTopBar(
                viewModel: viewModel,
                titleState: titleState,
                modeActions: actionStore.mode,
                scrollActions: actionStore.scroll,
                nativeRefreshActionStore: actionStore.nativeRefresh
            )
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
