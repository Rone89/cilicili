import SwiftUI
import UIKit

struct VideoDetailPlaybackSceneLayout {
    let effectiveFullscreenMode: PlayerFullscreenMode?
    let targetFullscreenMode: PlayerFullscreenMode?
    let usesFullscreenLayout: Bool
    let isLandscapeFullscreen: Bool
    let shouldHideSystemChrome: Bool
    let playbackSize: CGSize
    let fullscreenOffset: CGSize
    let supportedInterfaceOrientations: UIInterfaceOrientationMask

    init(
        proxy: GeometryProxy,
        fullscreenCoordinator: VideoDetailFullscreenCoordinator
    ) {
        let layoutFullscreenMode = fullscreenCoordinator.layoutMode
        let fullscreenGeometry = proxy.fullscreenContainerGeometry
        let fullscreenSize = fullscreenGeometry.size
        let stablePortraitWidth = VideoDetailStablePortraitLayout.width(
            proxySize: proxy.size,
            fullscreenSize: fullscreenSize
        )
        effectiveFullscreenMode = layoutFullscreenMode
        targetFullscreenMode = fullscreenCoordinator.layoutMode
        usesFullscreenLayout = layoutFullscreenMode != nil
        isLandscapeFullscreen = layoutFullscreenMode?.isLandscape == true
        shouldHideSystemChrome = fullscreenCoordinator.shouldHideSystemChrome
        playbackSize = usesFullscreenLayout
            ? fullscreenSize
            : CGSize(width: stablePortraitWidth, height: proxy.size.height)
        fullscreenOffset = usesFullscreenLayout ? fullscreenGeometry.offset : .zero
        supportedInterfaceOrientations = fullscreenCoordinator.mode?.videoDetailInterfaceOrientationMask ?? .portrait
    }
}
