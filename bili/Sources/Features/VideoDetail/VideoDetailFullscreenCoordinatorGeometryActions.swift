import UIKit

extension VideoDetailFullscreenCoordinator {
    func requestInlineFullscreenGeometry(for mode: PlayerFullscreenMode) {
        let scene = UIApplication.shared.videoDetailKeyWindow?.windowScene
            ?? UIApplication.shared.biliForegroundKeyWindow?.windowScene
        AppOrientationLock.update(
            to: mode.videoDetailInterfaceOrientationMask,
            in: scene,
            requestsGeometryUpdate: true
        )
    }

    func requestInlineFullscreenGeometryAfterLayout(for mode: PlayerFullscreenMode) {
        let revision = stateRevision
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self,
                  self.isCurrentStateRevision(revision),
                  self.mode == mode
            else { return }
            self.requestInlineFullscreenGeometry(for: mode)
        }
    }

    func requestInlinePortraitGeometry() {
        let scene = UIApplication.shared.videoDetailKeyWindow?.windowScene
            ?? UIApplication.shared.biliForegroundKeyWindow?.windowScene
        AppOrientationLock.update(
            to: .portrait,
            in: scene,
            requestsGeometryUpdate: true
        )
    }

    func requestInlinePortraitGeometryAfterLayout() {
        let revision = stateRevision
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self,
                  self.isCurrentStateRevision(revision),
                  self.mode == nil
            else { return }
            self.requestInlinePortraitGeometry()
        }
    }

    func preferredLandscapeDeviceOrientation() -> UIDeviceOrientation {
        if let orientation = UIApplication.shared.videoDetailKeyWindow?.windowScene?.effectiveGeometry.interfaceOrientation
            ?? UIApplication.shared.biliForegroundKeyWindow?.windowScene?.effectiveGeometry.interfaceOrientation,
           orientation.isLandscape {
            return orientation == .landscapeLeft ? .landscapeRight : .landscapeLeft
        }
        return .landscapeLeft
    }
}

extension PlayerFullscreenMode {
    var videoDetailInterfaceOrientationMask: UIInterfaceOrientationMask {
        switch self {
        case .portrait:
            return .portrait
        case .landscape(let orientation):
            switch orientation {
            case .landscapeLeft:
                return .landscapeRight
            case .landscapeRight:
                return .landscapeLeft
            default:
                return .landscapeRight
            }
        }
    }
}
