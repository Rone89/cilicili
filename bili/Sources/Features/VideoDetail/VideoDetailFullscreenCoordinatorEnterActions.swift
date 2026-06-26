import UIKit

extension VideoDetailFullscreenCoordinator {
    func enterFullscreen(
        playerViewModel: PlayerStateViewModel?,
        preferredLandscapeOrientation: UIDeviceOrientation? = nil,
        trigger: VideoDetailFullscreenTrigger,
        allowsInlineRotation: Bool,
        usesPortraitFullscreen: Bool,
        isCurrentPlayer: PlayerCurrentPredicate? = nil
    ) {
        advanceStateRevision()
        advanceFullscreenTransitionGeneration()
        cancelPendingFullscreenExitTask(advancesGeneration: false)
        cancelPendingSurfaceLayoutRefreshTask()
        exitingMode = nil
        isCompletingExit = false

        if let playerViewModel,
           !canRefreshSurface(for: playerViewModel, isCurrentPlayer: isCurrentPlayer) {
            pendingRotationLandscapeOrientation = nil
            return
        }

        guard allowsInlineRotation else {
            pendingRotationLandscapeOrientation = nil
            return
        }

        let targetMode = fullscreenTargetMode(
            preferredLandscapeOrientation: preferredLandscapeOrientation,
            usesPortraitFullscreen: usesPortraitFullscreen
        )

        let isRotationTriggered = trigger == .rotation
        if mode != nil {
            applyFullscreenTargetMode(
                targetMode,
                trigger: trigger,
                isRotationTriggered: isRotationTriggered,
                playerViewModel: playerViewModel,
                isCurrentPlayer: isCurrentPlayer
            )
            return
        }

        guard let playerViewModel else {
            if preferredLandscapeOrientation?.isLandscape == true {
                pendingRotationLandscapeOrientation = preferredLandscapeOrientation
            }
            return
        }

        applyFullscreenTargetMode(
            targetMode,
            trigger: trigger,
            isRotationTriggered: isRotationTriggered,
            playerViewModel: playerViewModel,
            isCurrentPlayer: isCurrentPlayer
        )
    }

}
