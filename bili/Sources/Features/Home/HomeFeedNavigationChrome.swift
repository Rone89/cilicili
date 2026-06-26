import SwiftUI

struct HomeFeedNavigationChrome: ViewModifier {
    @ObservedObject var viewModel: HomeViewModel
    let modeActions: HomeFeedModeActions

    func body(content: Content) -> some View {
        content
            .rootNavigationTitle("首页") {
                HomeFeedModeMenu(currentMode: viewModel.mode) { mode in
                    modeActions.switchMode(mode, viewModel: viewModel)
                }
            }
            .nativeTopNavigationChrome()
    }
}

extension View {
    func homeFeedNavigationChrome(
        viewModel: HomeViewModel,
        modeActions: HomeFeedModeActions
    ) -> some View {
        modifier(
            HomeFeedNavigationChrome(
                viewModel: viewModel,
                modeActions: modeActions
            )
        )
    }
}
