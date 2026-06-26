import SwiftUI

extension VideoDetailFullscreenCoordinator {
    func resetForDisappear() {
        advanceStateRevision()
        advanceFullscreenTransitionGeneration()
        cancelPendingFullscreenExitTask(advancesGeneration: false)
        cancelPendingSurfaceLayoutRefreshTask()
        cancelPendingPortraitExitSurfaceSettleTask(advancesGeneration: false)
        pendingRotationLandscapeOrientation = nil
        lastUsableMorphSnapshot = nil
        clearMorph(immediate: true)
        VideoDetailRotationWindowMask.remove()
        exitingMode = nil
        mode = nil
        trigger = .none
        isCompletingExit = false
        isSystemRotationLayoutTransitioning = false
        AppOrientationLock.restorePortrait()
    }

    func exitFullscreen(
        playerViewModel: PlayerStateViewModel?,
        isCurrentPlayer: PlayerCurrentPredicate? = nil
    ) {
        guard activeMode != nil else { return }
        pendingRotationLandscapeOrientation = nil
        cancelPendingPortraitExitSurfaceSettleTask(advancesGeneration: false)
        beginCompletingExit(
            playerViewModel: playerViewModel,
            isCurrentPlayer: isCurrentPlayer
        )
    }

    func beginRotationPortraitExit(
        playerViewModel: PlayerStateViewModel?,
        isCurrentPlayer: PlayerCurrentPredicate? = nil
    ) {
        guard activeMode != nil else { return }
        pendingRotationLandscapeOrientation = nil
        cancelPendingPortraitExitSurfaceSettleTask(advancesGeneration: false)
        beginCompletingExit(
            playerViewModel: playerViewModel,
            isCurrentPlayer: isCurrentPlayer
        )
    }

    func finishRotationPortraitExit(
        playerViewModel: PlayerStateViewModel?,
        isCurrentPlayer: PlayerCurrentPredicate? = nil
    ) {
        pendingRotationLandscapeOrientation = nil
        finishCompletingExit(
            playerViewModel: playerViewModel,
            isCurrentPlayer: isCurrentPlayer
        )
    }
}
