import UIKit

extension VideoDetailFullscreenCoordinator {
    func retryPendingRotationFullscreenIfNeeded(
        currentOrientation: UIDeviceOrientation,
        playerViewModel: PlayerStateViewModel?,
        decodePath: PlayerEngineDiagnostics.DecodePath?,
        allowsInlineRotation: Bool,
        usesPortraitFullscreen: Bool,
        isCurrentPlayer: PlayerCurrentPredicate? = nil
    ) {
        guard let retryOrientation = pendingRotationLandscapeOrientation
            ?? (currentOrientation.isLandscape ? currentOrientation : nil)
        else {
            return
        }

        guard !usesPortraitFullscreen else {
            pendingRotationLandscapeOrientation = nil
            requestInlinePortraitGeometry()
            return
        }

        guard canResolveRotationDecodePath(decodePath) else {
            pendingRotationLandscapeOrientation = retryOrientation
            return
        }

        guard canUseInlineRotation(allowsInlineRotation) else {
            pendingRotationLandscapeOrientation = nil
            return
        }

        enterFullscreen(
            playerViewModel: playerViewModel,
            preferredLandscapeOrientation: retryOrientation,
            trigger: .rotation,
            allowsInlineRotation: allowsInlineRotation,
            usesPortraitFullscreen: usesPortraitFullscreen,
            isCurrentPlayer: isCurrentPlayer
        )
    }
}
