import SwiftUI

struct BiliPlayerSpeedBoostActions {
    let viewModel: PlayerStateViewModel
    let surfaceState: PlayerSurfaceStateModel
    let speedBoostModel: PlayerSpeedBoostModel
    let visibilityActions: BiliPlayerPlaybackControlsVisibilityActions

    func beginIfNeeded() {
        guard !viewModel.isTerminated else { return }
        speedBoostModel.beginIfNeeded(
            playerViewModel: viewModel,
            isSurfacePlaying: surfaceState.isPlaying
        ) {
            visibilityActions.cancelAutoHide()
            visibilityActions.playbackControlsVisibility.hide(animated: true, duration: 0.12)
        }
    }

    func end(reason: String) {
        guard !viewModel.isTerminated else {
            speedBoostModel.cancel()
            return
        }
        speedBoostModel.end(
            reason: reason,
            playerViewModel: viewModel
        ) {
            visibilityActions.showAndSchedule()
        }
    }
}
