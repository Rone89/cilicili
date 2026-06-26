import SwiftUI

struct VideoDetailPlayerSurfaceContextSurfacesBuilder {
    let surfaceStore: VideoDetailPlayerSurfaceRenderStore
    let qualityControlStore: VideoDetailQualityControlRenderStore
    let danmakuStore: VideoDetailDanmakuRenderStore
    let playerViewModel: PlayerStateViewModel
    let configuration: VideoDetailPlayerSurfaceConfiguration
    let actions: VideoDetailPlayerSurfaceActions
    let onQualityControlPresentationChange: (Bool) -> Void

    var surfaces: VideoDetailPlayerSurfaceContextSurfaces {
        VideoDetailPlayerSurfaceContextSurfaces(
            surfaceOverlay: AnyView(
                VideoDetailPlayerSurfaceOverlayHost(
                    surfaceStore: surfaceStore,
                    danmakuStore: danmakuStore,
                    playerViewModel: playerViewModel,
                    usesLandscapePlaybackChrome: configuration.usesLandscapePlaybackChrome,
                    suppressesPosterDuringFullscreenTransition: configuration.suppressesPosterDuringFullscreenTransition,
                    onDanmakuPlaybackTime: actions.onDanmakuPlaybackTime
                )
            ),
            controlsAccessory: AnyView(
                VideoDetailPlayerSurfaceQualityControlHost(
                    store: qualityControlStore,
                    selectPlayVariant: actions.selectPlayVariant,
                    onPresentationChange: onQualityControlPresentationChange
                )
            ),
            topLeadingControlsAccessory: AnyView(
                VideoDetailPlayerSurfaceBackButtonHost(action: actions.onNavigateBack)
            )
        )
    }
}
