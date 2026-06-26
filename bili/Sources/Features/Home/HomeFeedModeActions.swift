import SwiftUI

@MainActor
final class HomeFeedModeActions {
    func switchMode(
        _ mode: HomeFeedMode,
        viewModel: HomeViewModel
    ) {
        Task { @MainActor in
            await viewModel.switchMode(mode)
        }
    }
}
