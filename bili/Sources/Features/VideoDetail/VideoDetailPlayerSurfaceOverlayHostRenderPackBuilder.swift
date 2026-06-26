import Foundation

struct VideoDetailPlayerSurfaceOverlayHostRenderPackBuilder {
    let usesLandscapePlaybackChrome: Bool
    let suppressesPosterDuringFullscreenTransition: Bool
    let onDanmakuPlaybackTime: (TimeInterval, Bool) -> Void

    var renderPack: VideoDetailPlayerSurfaceOverlayHostRenderPack {
        VideoDetailPlayerSurfaceOverlayHostRenderPack(
            configuration: configuration,
            actions: actions
        )
    }

    private var configuration: VideoDetailPlayerSurfaceOverlayConfiguration {
        VideoDetailPlayerSurfaceOverlayConfiguration(
            usesLandscapePlaybackChrome: usesLandscapePlaybackChrome,
            suppressesPosterDuringFullscreenTransition: suppressesPosterDuringFullscreenTransition
        )
    }

    private var actions: VideoDetailPlayerSurfaceOverlayActions {
        VideoDetailPlayerSurfaceOverlayActions(
            onDanmakuPlaybackTime: onDanmakuPlaybackTime
        )
    }
}
