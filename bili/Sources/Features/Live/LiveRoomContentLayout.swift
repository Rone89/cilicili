import SwiftUI
import UIKit

struct LiveRoomContentLayout {
    let proxySize: CGSize
    let fullscreenGeometry: LiveDetailFullscreenContainerGeometry
    let fullscreenMode: PlayerFullscreenMode?
    let isCompletingFullscreenExit: Bool

    var isInlineFullscreen: Bool {
        fullscreenMode != nil || isCompletingFullscreenExit
    }

    var isLandscape: Bool {
        sceneIsLandscape && !isInlineFullscreen
    }

    var shouldHideSystemChrome: Bool {
        isLandscape || isInlineFullscreen
    }

    var ignoresContainerSafeArea: Bool {
        isLandscape || isInlineFullscreen
    }

    var screenSize: CGSize {
        isLandscape ? fullscreenGeometry.size : layoutSize
    }

    var frameSize: CGSize {
        isLandscape ? fullscreenGeometry.size : layoutSize
    }

    var frameOffset: CGSize {
        isLandscape ? fullscreenGeometry.offset : .zero
    }

    private var sceneIsLandscape: Bool {
        proxySize.width > proxySize.height
    }

    private var layoutSize: CGSize {
        guard isInlineFullscreen else {
            return CGSize(width: stablePortraitLayoutWidth, height: proxySize.height)
        }

        if fullscreenMode?.isLandscape == true {
            return CGSize(
                width: max(proxySize.width, proxySize.height),
                height: min(proxySize.width, proxySize.height)
            )
        }

        return CGSize(
            width: min(proxySize.width, proxySize.height),
            height: max(proxySize.width, proxySize.height)
        )
    }

    private var stablePortraitLayoutWidth: CGFloat {
        let proxyShortSide = min(proxySize.width, proxySize.height)
        let fullscreenShortSide = min(fullscreenGeometry.size.width, fullscreenGeometry.size.height)
        let windowShortSide = UIApplication.shared.liveDetailForegroundKeyWindow.map { window in
            min(window.bounds.width, window.bounds.height)
        } ?? .greatestFiniteMagnitude
        return min(proxyShortSide, fullscreenShortSide, windowShortSide)
    }
}
