import SwiftUI

struct VideoDetailPlayerSurfaceDanmakuLayer: View {
    let store: VideoDetailDanmakuRenderStore
    let playerViewModel: PlayerStateViewModel
    let usesLandscapePlaybackChrome: Bool
    let logicalCanvasSize: CGSize?
    let videoAspectRatio: CGFloat
    var additionalTopInset: CGFloat = 0
    var additionalBottomInset: CGFloat = 0
    let isLayoutTransitioning: Bool
    let onPlaybackTime: (TimeInterval, Bool) -> Void

    var body: some View {
        VideoDetailDanmakuOverlay(
            store: store,
            playerViewModel: playerViewModel,
            clock: playerViewModel.playbackClock,
            usesLandscapePlaybackChrome: usesLandscapePlaybackChrome,
            logicalCanvasSize: logicalCanvasSize,
            videoAspectRatio: videoAspectRatio,
            additionalTopInset: additionalTopInset,
            additionalBottomInset: additionalBottomInset,
            isLayoutTransitioning: isLayoutTransitioning,
            onPlaybackTime: onPlaybackTime
        )
    }
}
