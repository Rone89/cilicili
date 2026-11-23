import SwiftUI
import UIKit

struct LiveRoomContentLayout {
    let proxySize: CGSize
    let fullscreenGeometry: PlaybackDetailFullscreenGeometry
    let fullscreenMode: PlayerFullscreenMode?
    let isCompletingFullscreenExit: Bool
    var horizontalSizeClass: UserInterfaceSizeClass? = nil

    var isInlineFullscreen: Bool {
        fullscreenMode != nil || isCompletingFullscreenExit
    }

    var isSplitTwoColumn: Bool {
        guard !isInlineFullscreen else { return false }
        return AdaptiveLayoutPolicy.videoDetailMode(
            containerSize: proxySize,
            horizontalSizeClass: horizontalSizeClass,
            isFullscreenActive: false,
            adaptiveEnabled: true
        ) == .twoColumnSplit
    }

    var isLandscape: Bool {
        guard !isSplitTwoColumn else { return false }
        if horizontalSizeClass == .regular {
            return false
        }
        return sceneIsLandscape && !isInlineFullscreen
    }

    var shouldHideSystemChrome: Bool {
        isLandscape || isInlineFullscreen
    }

    var ignoresContainerSafeArea: Bool {
        isLandscape || isInlineFullscreen
    }

    var screenSize: CGSize {
        if isLandscape { return fullscreenGeometry.size }
        if isSplitTwoColumn { return proxySize }
        return layoutSize
    }

    var frameSize: CGSize {
        if isLandscape { return fullscreenGeometry.size }
        if isSplitTwoColumn { return proxySize }
        return layoutSize
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
        PlaybackDetailStableLayout.portraitWidth(
            containerSize: proxySize,
            fullscreenSize: fullscreenGeometry.size,
            windowSize: UIApplication.shared.playbackDetailForegroundKeyWindow?.bounds.size
        )
    }
}
