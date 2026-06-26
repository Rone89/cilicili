import Combine
import SwiftUI

private struct VideoDetailPlaybackLoadHostModifier: ViewModifier {
    @ObservedObject var viewModel: VideoDetailViewModel
    @StateObject var state = VideoDetailPlaybackLoadHostState()
    let onPlayerIdentityChanged: @Sendable @MainActor () -> Void

    func body(content: Content) -> some View {
        let lifecycleActions = lifecycleActions
        content
            .task {
                await lifecycleActions.load()
            }
            .onReceive(viewModel.playerIdentityRenderStore.objectWillChange) { _ in
                lifecycleActions.schedulePlayerIdentityChanged()
            }
            .onChange(of: state.deliveredPlayerIdentityChangeGeneration) { _, generation in
                lifecycleActions.deliverPlayerIdentityChanged(generation: generation)
            }
            .onDisappear {
                lifecycleActions.cancelPendingWork()
            }
    }

    private var lifecycleActions: VideoDetailPlaybackLoadHostLifecycleActions {
        let playerIdentityChanged = onPlayerIdentityChanged
        return VideoDetailPlaybackLoadHostLifecycleActions(
            actions: VideoDetailPlaybackLoadHostActionsBuilder(
                viewModel: viewModel
            )
            .actions,
            state: state,
            onPlayerIdentityChanged: {
                playerIdentityChanged()
            }
        )
    }
}

extension View {
    func videoDetailPlaybackLoadHost(
        viewModel: VideoDetailViewModel,
        onPlayerIdentityChanged: @escaping @Sendable @MainActor () -> Void
    ) -> some View {
        modifier(
            VideoDetailPlaybackLoadHostModifier(
                viewModel: viewModel,
                onPlayerIdentityChanged: onPlayerIdentityChanged
            )
        )
    }
}
