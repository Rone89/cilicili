import UIKit

@MainActor
struct VideoDetailPlaybackSceneFullscreenOrientationActions {
    let context: VideoDetailPlaybackSceneFullscreenActionContext

    func handleCurrentDeviceOrientation() {
        guard canHandleOrientationChange() else { return }
        handleFullscreenDeviceOrientation(with: context.playback)
    }

    func refreshActivePlayerSurfaceLayout(coordinatedWithSwiftUILayout: Bool = false) {
        guard canHandleOrientationChange() else { return }
        context.fullscreenCoordinator.refreshActivePlayerSurfaceLayout(
            playerViewModel: context.playback.playerViewModel,
            coordinatedWithSwiftUILayout: coordinatedWithSwiftUILayout,
            isCurrentPlayer: context.isCurrentPlayer
        )
    }

    func beginSystemRotationLayoutTransition() {
        guard canHandleOrientationChange() else { return }
        context.fullscreenCoordinator.beginSystemRotationLayoutTransition(
            playerViewModel: context.playback.playerViewModel,
            isCurrentPlayer: context.isCurrentPlayer
        )
    }

    func finishSystemRotationLayoutTransition() {
        guard canHandleOrientationChange() else { return }
        context.fullscreenCoordinator.finishSystemRotationLayoutTransition(
            playerViewModel: context.playback.playerViewModel,
            isCurrentPlayer: context.isCurrentPlayer
        )
    }

    private func handleFullscreenDeviceOrientation(with playback: VideoDetailPlaybackContext) {
        context.fullscreenCoordinator.handleDeviceOrientation(
            resolvedDeviceOrientation,
            playerViewModel: playback.playerViewModel,
            decodePath: playback.decodePath,
            allowsInlineRotation: playback.allowsInlineFullscreenRotation,
            usesPortraitFullscreen: playback.usesPortraitFullscreen,
            isCurrentPlayer: context.isCurrentPlayer
        )
    }

    private func canHandleOrientationChange() -> Bool {
        guard context.canHandlePlaybackPresentation else {
            context.fullscreenCoordinator.resetForDisappear()
            return false
        }
        return true
    }

    private var resolvedDeviceOrientation: UIDeviceOrientation {
        let current = UIDevice.current.orientation
        if current.isPortrait || current.isLandscape {
            return current
        }
        return UIApplication.shared.videoDetailKeyWindow?.windowScene?.effectiveGeometry.interfaceOrientation.videoDetailDeviceOrientation
            ?? UIApplication.shared.biliForegroundKeyWindow?.windowScene?.effectiveGeometry.interfaceOrientation.videoDetailDeviceOrientation
            ?? .portrait
    }
}

private extension UIInterfaceOrientation {
    var videoDetailDeviceOrientation: UIDeviceOrientation {
        switch self {
        case .landscapeLeft:
            return .landscapeRight
        case .landscapeRight:
            return .landscapeLeft
        case .portraitUpsideDown:
            return .portraitUpsideDown
        default:
            return .portrait
        }
    }
}
