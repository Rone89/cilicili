import SwiftUI

struct HomeView: View {
    @Environment(\.homeTopBarActions) private var topBarActions
    @EnvironmentObject private var libraryStore: LibraryStore
    let launchConfiguration: HomeFeedLaunchConfiguration
    let actionStore: HomeFeedScreenActionStore
    @ObservedObject private var viewModel: HomeViewModel
    @Binding var detailPath: NavigationPath
    @Binding var showsLiveFeed: Bool
    @StateObject private var titleState = FeedChromeTitleState()
    @StateObject private var liveFeedHolder = LiveViewModelHolder()

    init(
        viewModel: HomeViewModel,
        detailPath: Binding<NavigationPath>,
        showsLiveFeed: Binding<Bool>,
        actionStore: HomeFeedScreenActionStore,
        launchConfiguration: HomeFeedLaunchConfiguration
    ) {
        self.viewModel = viewModel
        _detailPath = detailPath
        _showsLiveFeed = showsLiveFeed
        self.actionStore = actionStore
        self.launchConfiguration = launchConfiguration
    }

    var body: some View {
        Group {
            if showsLiveFeed {
                LiveFeedScreenContent(holder: liveFeedHolder)
            } else {
                HomeFeedScreenContent(
                    viewModel: viewModel,
                    detailPath: $detailPath,
                    actionStore: actionStore,
                    launchConfiguration: launchConfiguration
                )
            }
        }
        .environment(\.feedChromeTitleState, titleState)
        .contentMargins(.top, 12, for: .scrollContent)
        .toolbar {
            HomeTopBar(
                selection: showsLiveFeed ? .live : .feed(viewModel.mode),
                titleState: titleState,
                hiddenTabs: AppTab.allCases.filter {
                    $0.canHideFromRootTabBar && !libraryStore.visibleRootTabs.contains($0)
                },
                actions: topBarActions,
                liveViewModel: showsLiveFeed ? liveFeedHolder.viewModel : nil,
                onSelect: selectPage
            )
        }
        .toolbarVisibility(.visible, for: .navigationBar)
        .onChange(of: showsLiveFeed) { _, _ in titleState.reset() }
    }

    private func selectPage(_ selection: HomePageSelection) {
        guard case .feed(let mode) = selection else {
            showsLiveFeed = true
            return
        }
        showsLiveFeed = false
        actionStore.mode.switchMode(
            mode,
            viewModel: viewModel,
            scrollActions: actionStore.scroll,
            nativeRefreshActionStore: actionStore.nativeRefresh
        )
    }
}
