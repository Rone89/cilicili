import SwiftUI

struct HomeView: View {
    let launchConfiguration: HomeFeedLaunchConfiguration
    @ObservedObject private var viewModel: HomeViewModel
    @Binding var detailPath: NavigationPath

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
        HomeFeedScreenContent(
            viewModel: viewModel,
            detailPath: $detailPath,
            launchConfiguration: launchConfiguration
        )
    }
}
