import SwiftUI

struct VideoDetailPlayerSurfaceOverlayHost: View {
    @ObservedObject var surfaceStore: VideoDetailPlayerSurfaceRenderStore
    @ObservedObject var danmakuStore: VideoDetailDanmakuRenderStore
    @ObservedObject var playerViewModel: PlayerStateViewModel
    let renderPack: VideoDetailPlayerSurfaceOverlayHostRenderPack

    init(
        surfaceStore: VideoDetailPlayerSurfaceRenderStore,
        danmakuStore: VideoDetailDanmakuRenderStore,
        playerViewModel: PlayerStateViewModel,
        usesLandscapePlaybackChrome: Bool,
        suppressesPosterDuringFullscreenTransition: Bool,
        onDanmakuPlaybackTime: @escaping (TimeInterval, Bool) -> Void
    ) {
        self.surfaceStore = surfaceStore
        self.danmakuStore = danmakuStore
        self.playerViewModel = playerViewModel
        renderPack = VideoDetailPlayerSurfaceOverlayHostRenderPackBuilder(
            usesLandscapePlaybackChrome: usesLandscapePlaybackChrome,
            suppressesPosterDuringFullscreenTransition: suppressesPosterDuringFullscreenTransition,
            onDanmakuPlaybackTime: onDanmakuPlaybackTime
        )
        .renderPack
    }

    var body: some View {
        VideoDetailPlayerSurfaceOverlay(
            surfaceStore: surfaceStore,
            danmakuStore: danmakuStore,
            playerViewModel: playerViewModel,
            configuration: renderPack.configuration,
            actions: renderPack.actions
        )
    }
}
