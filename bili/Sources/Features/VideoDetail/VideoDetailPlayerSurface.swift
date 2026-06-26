import SwiftUI

struct VideoDetailPlayerSurface: View {
    @ObservedObject var surfaceStore: VideoDetailPlayerSurfaceRenderStore
    let qualityControlStore: VideoDetailQualityControlRenderStore
    let danmakuStore: VideoDetailDanmakuRenderStore
    let playerViewModel: PlayerStateViewModel
    let configuration: VideoDetailPlayerSurfaceConfiguration
    let actions: VideoDetailPlayerSurfaceActions
    let allowsPlaybackActivation: () -> Bool
    @State private var presentationState = VideoDetailPlayerSurfacePresentationState()

    var body: some View {
        let renderPack = resolvedRenderPack

        BiliPlayerView(
            viewModel: playerViewModel,
            historyVideo: surfaceStore.historyVideo,
            historyCID: surfaceStore.historyCID,
            options: renderPack.options
        )
        .id(ObjectIdentifier(playerViewModel))
        .frame(width: configuration.playerWidth)
        .frame(height: configuration.playerHeight)
        .background(Color.black)
        .videoDetailReportPlayerSurfaceFrame()
        .animation(surfaceSizeAnimation, value: configuration.playerWidth)
        .animation(surfaceSizeAnimation, value: configuration.playerHeight)
    }

    private var surfaceSizeAnimation: Animation? {
        configuration.isLayoutTransitioning || configuration.fullscreenMode?.isLandscape == true
            ? nil
            : VideoDetailFullscreenCoordinator.inlineTransitionAnimation
    }

    private var resolvedRenderPack: VideoDetailPlayerSurfaceRenderPack {
        VideoDetailPlayerSurfaceRenderPackBuilder(
            surfaceStore: surfaceStore,
            qualityControlStore: qualityControlStore,
            danmakuStore: danmakuStore,
            playerViewModel: playerViewModel,
            configuration: configuration,
            actions: actions,
            allowsPlaybackActivation: allowsPlaybackActivation,
            presentationState: presentationState,
            presentationActions: presentationActions
        )
        .renderPack
    }

    private var presentationActions: VideoDetailPlayerSurfacePresentationActions {
        VideoDetailPlayerSurfacePresentationActions(state: $presentationState)
    }
}
