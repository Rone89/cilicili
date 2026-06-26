import Foundation

struct PlaybackPosterOverlayLifecycleActions {
    let playerViewModel: PlayerStateViewModel
    let state: PlaybackPosterOverlayState

    func bindPlayer() {
        state.bind(playerViewModel: playerViewModel)
    }

    func unbindPlayer() {
        state.unbind()
    }
}
