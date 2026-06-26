import UIKit

extension VideoDetailFullscreenCoordinator {
    func handleDeviceOrientation(
        _ orientation: UIDeviceOrientation,
        playerViewModel: PlayerStateViewModel?,
        decodePath: PlayerEngineDiagnostics.DecodePath?,
        allowsInlineRotation: Bool,
        usesPortraitFullscreen: Bool,
        isCurrentPlayer: PlayerCurrentPredicate? = nil
    ) {
        guard canResolveRotationDecodePath(decodePath) else {
            if orientation.isLandscape {
                pendingRotationLandscapeOrientation = orientation
            } else if orientation.isPortrait {
                pendingRotationLandscapeOrientation = nil
            }
            return
        }

        guard canUseInlineRotation(allowsInlineRotation) else {
            pendingRotationLandscapeOrientation = nil
            return
        }

        switch orientation {
        case .landscapeLeft, .landscapeRight:
            guard !usesPortraitFullscreen else {
                pendingRotationLandscapeOrientation = nil
                requestInlinePortraitGeometry()
                return
            }
            pendingRotationLandscapeOrientation = orientation
            enterFullscreen(
                playerViewModel: playerViewModel,
                preferredLandscapeOrientation: orientation,
                trigger: trigger == .none ? .rotation : trigger,
                allowsInlineRotation: allowsInlineRotation,
                usesPortraitFullscreen: usesPortraitFullscreen,
                isCurrentPlayer: isCurrentPlayer
            )
        case .portrait, .portraitUpsideDown:
            pendingRotationLandscapeOrientation = nil
            guard mode?.isLandscape == true else { return }
            guard trigger == .rotation else { return }
            beginRotationPortraitExit(
                playerViewModel: playerViewModel,
                isCurrentPlayer: isCurrentPlayer
            )
        default:
            break
        }
    }

}
