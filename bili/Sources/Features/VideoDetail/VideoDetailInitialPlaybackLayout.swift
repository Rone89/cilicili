import SwiftUI
import UIKit

struct VideoDetailInitialPlaybackLayout {
    let width: CGFloat
    let playerHeight: CGFloat

    init(proxy: GeometryProxy, videoAspectRatio: CGFloat) {
        let fullscreenSize = proxy.fullscreenContainerGeometry.size
        width = PlaybackDetailStableLayout.portraitWidth(
            containerSize: proxy.size,
            fullscreenSize: fullscreenSize,
            windowSize: UIApplication.shared.playbackDetailForegroundKeyWindow?.bounds.size
        )

        let standardHeight = PlaybackDetailPlayerMetrics.standardHeight(for: width)
        if VideoDetailShellLayout.usesFullWidthAspectRatioVideo(videoAspectRatio: videoAspectRatio) {
            playerHeight = width / videoAspectRatio
        } else if videoAspectRatio < 0.9 {
            let proposedHeight = max(proxy.size.height * 0.65, width)
            let maximumHeight = max(standardHeight, proxy.size.height * 0.72)
            playerHeight = max(standardHeight, min(proposedHeight, maximumHeight))
        } else {
            playerHeight = standardHeight
        }
    }
}
