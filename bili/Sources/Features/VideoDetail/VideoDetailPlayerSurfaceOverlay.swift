import SwiftUI

struct VideoDetailPlayerSurfaceOverlay: View {
    @ObservedObject var surfaceStore: VideoDetailPlayerSurfaceRenderStore
    let danmakuStore: VideoDetailDanmakuRenderStore
    @ObservedObject var playerViewModel: PlayerStateViewModel
    let configuration: VideoDetailPlayerSurfaceOverlayConfiguration
    let actions: VideoDetailPlayerSurfaceOverlayActions

    var body: some View {
        ZStack {
            VideoDetailPlayerSurfaceDanmakuLayer(
                store: danmakuStore,
                playerViewModel: playerViewModel,
                usesLandscapePlaybackChrome: configuration.usesLandscapePlaybackChrome,
                onPlaybackTime: actions.onDanmakuPlaybackTime
            )

            if let historyVideo = surfaceStore.historyVideo,
               shouldShowPosterOverlay {
                PlaybackPosterOverlay(
                    video: historyVideo,
                    playerViewModel: playerViewModel,
                    dimOpacity: 0.36,
                    showsLoader: true
                )
            }
        }
    }

    private var shouldShowPosterOverlay: Bool {
        !playerViewModel.hasPresentedPlayback
            && !configuration.suppressesPosterDuringFullscreenTransition
    }
}
