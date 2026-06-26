import SwiftUI
import UIKit

struct VideoDetailInitialPlaybackLayout {
    let width: CGFloat
    let playerHeight: CGFloat

    init(proxy: GeometryProxy, isPortraitVideo: Bool) {
        let fullscreenSize = proxy.fullscreenContainerGeometry.size
        width = VideoDetailStablePortraitLayout.width(
            proxySize: proxy.size,
            fullscreenSize: fullscreenSize
        )

        let standardHeight = width * 9 / 16
        let headerLayout = VideoDetailPinnedDynamicPlayerHeaderLayout(
            screenSize: CGSize(width: width, height: proxy.size.height),
            standardHeight: standardHeight,
            isPortraitVideo: isPortraitVideo,
            isEnabled: true
        )
        playerHeight = headerLayout.expandedHeight
    }
}

enum VideoDetailStablePortraitLayout {
    static func width(proxySize: CGSize, fullscreenSize: CGSize) -> CGFloat {
        let proxyShortSide = min(proxySize.width, proxySize.height)
        let fullscreenShortSide = min(fullscreenSize.width, fullscreenSize.height)
        let windowShortSide = UIApplication.shared.biliForegroundKeyWindow.map { window in
            min(window.bounds.width, window.bounds.height)
        } ?? .greatestFiniteMagnitude
        return min(proxyShortSide, fullscreenShortSide, windowShortSide)
    }
}
