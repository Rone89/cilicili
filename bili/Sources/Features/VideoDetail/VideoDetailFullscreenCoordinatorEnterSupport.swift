import UIKit

extension VideoDetailFullscreenCoordinator {
    func fullscreenTargetMode(
        preferredLandscapeOrientation: UIDeviceOrientation?,
        usesPortraitFullscreen: Bool
    ) -> PlayerFullscreenMode {
        guard !usesPortraitFullscreen else { return .portrait }
        let landscapeOrientation = preferredLandscapeOrientation?.isLandscape == true
            ? preferredLandscapeOrientation!
            : preferredLandscapeDeviceOrientation()
        return .landscape(landscapeOrientation)
    }

    func applyFullscreenTargetMode(
        _ targetMode: PlayerFullscreenMode,
        trigger: VideoDetailFullscreenTrigger,
        isRotationTriggered: Bool,
        playerViewModel: PlayerStateViewModel?,
        isCurrentPlayer: PlayerCurrentPredicate? = nil
    ) {
        // 进入全屏（竖→横）也用静态快照盖住旋转 + surface 重建过程，
        // 避免播放区域在旋转瞬间露出黑色背景（黑闪）。
        let orientation: UIDeviceOrientation
        if case let .landscape(landscapeOrientation) = targetMode {
            orientation = landscapeOrientation
        } else {
            orientation = preferredLandscapeDeviceOrientation()
        }
        prepareEnterMorph(
            playerViewModel: playerViewModel,
            orientation: orientation,
            usesWindowMask: isRotationTriggered && targetMode.isLandscape
        )
        if isRotationTriggered, !isSystemRotationLayoutTransitioning {
            isSystemRotationLayoutTransitioning = true
        }
        setMode(
            targetMode,
            trigger: trigger,
            animated: !isRotationTriggered,
            playerViewModel: playerViewModel,
            isCurrentPlayer: isCurrentPlayer
        )
        requestInlineFullscreenGeometryAfterLayout(for: targetMode)
        runPreparedEnterMorphAfterLayout()
    }
}
