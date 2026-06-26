import SwiftUI

struct VideoDetailPlayerSurfaceRenderPackBuilder {
    let surfaceStore: VideoDetailPlayerSurfaceRenderStore
    let qualityControlStore: VideoDetailQualityControlRenderStore
    let danmakuStore: VideoDetailDanmakuRenderStore
    let playerViewModel: PlayerStateViewModel
    let configuration: VideoDetailPlayerSurfaceConfiguration
    let actions: VideoDetailPlayerSurfaceActions
    let allowsPlaybackActivation: () -> Bool
    let presentationState: VideoDetailPlayerSurfacePresentationState
    let presentationActions: VideoDetailPlayerSurfacePresentationActions

    var renderPack: VideoDetailPlayerSurfaceRenderPack {
        let context = surfaceContext
        return VideoDetailPlayerSurfaceRenderPack(
            context: context,
            options: playerOptions(for: context)
        )
    }

    private var surfaceContext: VideoDetailPlayerSurfaceContext {
        VideoDetailPlayerSurfaceContextBuilder(
            surfaceStore: surfaceStore,
            qualityControlStore: qualityControlStore,
            danmakuStore: danmakuStore,
            playerViewModel: playerViewModel,
            configuration: configuration,
            actions: actions,
            isShowingQualityControls: presentationState.isShowingQualityControls,
            onQualityControlPresentationChange: presentationActions.updateQualityControlPresentation
        ).context
    }

    private func playerOptions(for context: VideoDetailPlayerSurfaceContext) -> BiliPlayerViewOptions {
        VideoDetailPlayerSurfaceOptionsBuilder(
            context: context,
            surfaceStore: surfaceStore,
            configuration: configuration,
            allowsPlaybackActivation: allowsPlaybackActivation
        ).options
    }
}
