import SwiftUI

private struct HomeFeedScrollOverlayModifier: ViewModifier {
    @ObservedObject var viewModel: HomeViewModel

    func body(content: Content) -> some View {
        content
            .overlay {
                HomeFeedFailureOverlay(
                    state: viewModel.state,
                    isEmpty: viewModel.videos.isEmpty,
                    retry: { Task { await viewModel.refresh() } }
                )
            }
    }
}

extension View {
    func homeFeedScrollOverlays(
        viewModel: HomeViewModel
    ) -> some View {
        modifier(
            HomeFeedScrollOverlayModifier(
                viewModel: viewModel
            )
        )
    }
}
