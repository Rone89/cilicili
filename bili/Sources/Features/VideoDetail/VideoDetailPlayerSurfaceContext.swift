import SwiftUI

struct VideoDetailPlayerSurfaceContext {
    let presentation: BiliPlayerPresentation
    let showsPlaybackControls: Bool
    let isSecondaryControlsPresented: Bool
    let surfaces: VideoDetailPlayerSurfaceContextSurfaces
    let controls: VideoDetailPlayerSurfaceContextControls
}

struct VideoDetailPlayerSurfaceContextBuilder {
    let surfaceStore: VideoDetailPlayerSurfaceRenderStore
    let qualityControlStore: VideoDetailQualityControlRenderStore
    let danmakuStore: VideoDetailDanmakuRenderStore
    let playerViewModel: PlayerStateViewModel
    let configuration: VideoDetailPlayerSurfaceConfiguration
    let actions: VideoDetailPlayerSurfaceActions
    let isShowingQualityControls: Bool
    let onQualityControlPresentationChange: (Bool) -> Void

    var context: VideoDetailPlayerSurfaceContext {
        VideoDetailPlayerSurfaceContext(
            presentation: configuration.usesLandscapePlaybackChrome ? .fullScreen : .embedded,
            showsPlaybackControls: configuration.showsPlaybackControls,
            isSecondaryControlsPresented: isShowingQualityControls || configuration.isDanmakuSettingsPresented,
            surfaces: surfacesBuilder.surfaces,
            controls: controlsBuilder.controls
        )
    }

    private var surfacesBuilder: VideoDetailPlayerSurfaceContextSurfacesBuilder {
        VideoDetailPlayerSurfaceContextSurfacesBuilder(
            surfaceStore: surfaceStore,
            qualityControlStore: qualityControlStore,
            danmakuStore: danmakuStore,
            playerViewModel: playerViewModel,
            configuration: configuration,
            actions: actions,
            onQualityControlPresentationChange: onQualityControlPresentationChange
        )
    }

    private var controlsBuilder: VideoDetailPlayerSurfaceContextControlsBuilder {
        VideoDetailPlayerSurfaceContextControlsBuilder(
            playerViewModel: playerViewModel,
            actions: actions
        )
    }
}
