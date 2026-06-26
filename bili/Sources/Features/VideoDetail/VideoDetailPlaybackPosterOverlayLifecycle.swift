import SwiftUI

private struct PlaybackPosterOverlayLifecycleModifier: ViewModifier {
    let playerViewModel: PlayerStateViewModel
    let actions: PlaybackPosterOverlayLifecycleActions

    func body(content: Content) -> some View {
        content
            .onAppear(perform: actions.bindPlayer)
            .onChange(of: ObjectIdentifier(playerViewModel)) { _, _ in
                actions.bindPlayer()
            }
            .onDisappear(perform: actions.unbindPlayer)
    }
}

extension View {
    func playbackPosterOverlayLifecycle(
        playerViewModel: PlayerStateViewModel,
        state: PlaybackPosterOverlayState
    ) -> some View {
        modifier(
            PlaybackPosterOverlayLifecycleModifier(
                playerViewModel: playerViewModel,
                actions: PlaybackPosterOverlayLifecycleActions(
                    playerViewModel: playerViewModel,
                    state: state
                )
            )
        )
    }
}
