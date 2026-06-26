import SwiftUI

struct VideoDetailPlaybackSceneLayer: View {
    @ObservedObject var viewModel: VideoDetailViewModel
    @ObservedObject var fullscreenCoordinator: VideoDetailFullscreenCoordinator
    let proxySize: CGSize
    let layout: VideoDetailPlaybackSceneLayout
    let standardPlaybackConfig: VideoDetailStandardPlaybackContainerConfig
    @Binding var selectedContentTab: VideoDetailContentTab
    let actions: VideoDetailStandardPlaybackActions

    var body: some View {
        ZStack(alignment: .topLeading) {
            VideoDetailPlaybackFullscreenBackdrop(
                usesFullscreenLayout: layout.usesFullscreenLayout
            )

            VideoDetailPlaybackContainerHost(
                viewModel: viewModel,
                layout: layout,
                standardPlaybackConfig: standardPlaybackConfig,
                selectedContentTab: $selectedContentTab,
                actions: actions
            )

            VideoDetailFullscreenMorphOverlay(
                state: fullscreenCoordinator.morphState
            )

        }
        .frame(width: proxySize.width, height: proxySize.height, alignment: .topLeading)
        .onPreferenceChange(VideoDetailPlayerSurfaceFramePreferenceKey.self) { frame in
            fullscreenCoordinator.updatePlayerSurfaceFrame(frame)
        }
        .videoDetailPlaybackSceneLayerAnimations(
            fullscreenCoordinator: fullscreenCoordinator,
            layout: layout
        )
        .background(layout.usesFullscreenLayout ? Color.black : VideoDetailTheme.background)
        .ignoresSafeArea(.container, edges: layout.usesFullscreenLayout ? .all : [])
    }
}
