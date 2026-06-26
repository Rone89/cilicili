import SwiftUI

struct BiliPlayerSurfaceGestureActions {
    let viewModel: PlayerStateViewModel
    let visibilityActions: BiliPlayerPlaybackControlsVisibilityActions
    let speedBoostActions: BiliPlayerSpeedBoostActions

    func singleTap() {
        guard !viewModel.isTerminated else { return }
        viewModel.togglePlayback()
        visibilityActions.showAndSchedule()
    }

    func doubleTap() {
        guard !viewModel.isTerminated else { return }
        visibilityActions.toggle()
    }

    func beginSpeedBoost() {
        guard !viewModel.isTerminated else { return }
        speedBoostActions.beginIfNeeded()
    }

    func endSpeedBoost() {
        guard !viewModel.isTerminated else {
            speedBoostActions.end(reason: "terminated")
            return
        }
        speedBoostActions.end(reason: "gestureEnded")
    }
}
