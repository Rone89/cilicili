import SwiftUI
import UIKit

extension LiveRoomContentView {
    func toggleDescriptionSheet() {
        isShowingDescription = true
    }

    func enterInlineFullscreenPlayback(playerViewModel: PlayerStateViewModel? = nil) {
        pendingFullscreenExitTask?.cancel()
        isCompletingFullscreenExit = false

        let orientation = UIDevice.current.orientation
        let targetMode = PlayerFullscreenMode.landscape(orientation.isLandscape ? orientation : .landscapeRight)
        guard fullscreenMode != targetMode else {
            requestLiveFullscreenGeometry(for: targetMode)
            playerViewModel?.refreshSurfaceLayout()
            return
        }
        withAnimation(.timingCurve(0.2, 0.92, 0.18, 1, duration: 0.42)) {
            fullscreenMode = targetMode
        }

        requestLiveFullscreenGeometry(for: targetMode)
        playerViewModel?.refreshSurfaceLayout()
    }

    func exitInlineFullscreenPlayback(playerViewModel: PlayerStateViewModel? = nil) {
        guard fullscreenMode != nil else { return }
        pendingFullscreenExitTask?.cancel()
        isCompletingFullscreenExit = true

        withAnimation(.timingCurve(0.2, 0.92, 0.18, 1, duration: 0.42)) {
            fullscreenMode = nil
        }
        playerViewModel?.refreshSurfaceLayout()

        pendingFullscreenExitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled else { return }
            isCompletingFullscreenExit = false
            requestLivePortraitGeometry()
            allowLiveAutoRotation()
        }
    }

    func requestLiveFullscreenGeometry(for mode: PlayerFullscreenMode) {
        if let windowScene = UIApplication.shared.liveDetailForegroundKeyWindow?.windowScene {
            AppOrientationLock.update(
                to: mode.liveDetailInterfaceOrientationMask,
                in: windowScene,
                requestsGeometryUpdate: true
            )
        }
    }

    func requestLivePortraitGeometry() {
        if let windowScene = UIApplication.shared.liveDetailForegroundKeyWindow?.windowScene {
            AppOrientationLock.update(to: Self.supportedLiveOrientations, in: windowScene)
            AppOrientationLock.requestGeometryUpdate(to: .portrait, in: windowScene)
        } else {
            AppOrientationLock.update(to: Self.supportedLiveOrientations, in: nil)
        }
    }

    func allowLiveAutoRotation() {
        AppOrientationLock.update(
            to: Self.supportedLiveOrientations,
            in: UIApplication.shared.liveDetailForegroundKeyWindow?.windowScene
        )
    }

    func updateLiveFullscreenOrientation(_ orientation: UIDeviceOrientation) {
        switch orientation {
        case .landscapeLeft, .landscapeRight:
            guard fullscreenMode?.isLandscape != true else { return }
            enterInlineFullscreenPlayback(playerViewModel: viewModel.playerViewModel)
        case .portrait, .portraitUpsideDown:
            guard fullscreenMode?.isLandscape == true else { return }
            exitInlineFullscreenPlayback(playerViewModel: viewModel.playerViewModel)
        default:
            break
        }
    }
}
