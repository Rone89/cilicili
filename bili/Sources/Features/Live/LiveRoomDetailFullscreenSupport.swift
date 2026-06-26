import SwiftUI
import UIKit

struct LiveDetailFullscreenContainerGeometry {
    let size: CGSize
    let offset: CGSize
}

extension GeometryProxy {
    var liveDetailFullscreenContainerGeometry: LiveDetailFullscreenContainerGeometry {
        if let window = UIApplication.shared.liveDetailForegroundKeyWindow,
           let rootView = window.rootViewController?.view {
            let localFrame = frame(in: .global)
            let frameInWindow = rootView.convert(localFrame, from: nil)
            return LiveDetailFullscreenContainerGeometry(
                size: window.bounds.size,
                offset: CGSize(width: -frameInWindow.minX, height: -frameInWindow.minY)
            )
        }

        let expandedSize = CGSize(
            width: size.width + safeAreaInsets.leading + safeAreaInsets.trailing,
            height: size.height + safeAreaInsets.top + safeAreaInsets.bottom
        )
        return LiveDetailFullscreenContainerGeometry(
            size: expandedSize,
            offset: CGSize(width: -safeAreaInsets.leading, height: -safeAreaInsets.top)
        )
    }
}

extension UIApplication {
    var liveDetailForegroundKeyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }
}

extension PlayerFullscreenMode {
    var liveDetailInterfaceOrientationMask: UIInterfaceOrientationMask {
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
