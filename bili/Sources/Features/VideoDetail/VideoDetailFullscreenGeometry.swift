import SwiftUI
import UIKit

struct FullscreenContainerGeometry {
    let size: CGSize
    let offset: CGSize
}

extension GeometryProxy {
    var fullscreenContainerGeometry: FullscreenContainerGeometry {
        if let window = UIApplication.shared.biliForegroundKeyWindow,
           let rootView = window.rootViewController?.view {
            let localFrame = frame(in: .global)
            let frameInWindow = rootView.convert(localFrame, from: nil)
            let resolvedSize = Self.resolvedFullscreenSize(
                windowSize: window.bounds.size,
                rootSize: rootView.bounds.size,
                orientation: window.windowScene?.effectiveGeometry.interfaceOrientation
            )
            return FullscreenContainerGeometry(
                size: resolvedSize,
                offset: CGSize(width: -frameInWindow.minX, height: -frameInWindow.minY)
            )
        }

        let expandedSize = CGSize(
            width: size.width + safeAreaInsets.leading + safeAreaInsets.trailing,
            height: size.height + safeAreaInsets.top + safeAreaInsets.bottom
        )
        return FullscreenContainerGeometry(
            size: expandedSize,
            offset: CGSize(width: -safeAreaInsets.leading, height: -safeAreaInsets.top)
        )
    }

    private static func resolvedFullscreenSize(
        windowSize: CGSize,
        rootSize: CGSize,
        orientation: UIInterfaceOrientation?
    ) -> CGSize {
        let candidates = [rootSize, windowSize].filter { $0.width > 1 && $0.height > 1 }
        guard let orientation else {
            return candidates.first ?? windowSize
        }

        if orientation.isLandscape {
            if let landscapeSize = candidates.first(where: { $0.width >= $0.height }) {
                return landscapeSize
            }
            let fallback = candidates.first ?? windowSize
            return CGSize(width: max(fallback.width, fallback.height), height: min(fallback.width, fallback.height))
        }

        if orientation.isPortrait {
            if let portraitSize = candidates.first(where: { $0.height >= $0.width }) {
                return portraitSize
            }
            let fallback = candidates.first ?? windowSize
            return CGSize(width: min(fallback.width, fallback.height), height: max(fallback.width, fallback.height))
        }

        return candidates.first ?? windowSize
    }
}
