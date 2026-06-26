import SwiftUI

struct VideoDetailPlaybackSceneResolvedContent: View {
    @ObservedObject var viewModel: VideoDetailViewModel
    @ObservedObject var fullscreenCoordinator: VideoDetailFullscreenCoordinator
    @ObservedObject var libraryStore: LibraryStore
    let scenePhase: ScenePhase
    let proxySize: CGSize
    let renderPack: VideoDetailPlaybackSceneContentRenderPack
    let bindings: VideoDetailPlaybackSceneBindings
    let actions: VideoDetailPlaybackSceneActions

    var body: some View {
        VideoDetailPlaybackSceneLayer(
            viewModel: viewModel,
            fullscreenCoordinator: fullscreenCoordinator,
            proxySize: proxySize,
            layout: renderPack.context.layout,
            standardPlaybackConfig: renderPack.standardPlaybackConfig,
            selectedContentTab: bindings.selectedContentTab,
            actions: actions.standardPlayback
        )
        .videoDetailPlaybackSceneHosts(
            viewModel: viewModel,
            libraryStore: libraryStore,
            scenePhase: scenePhase,
            context: renderPack.context,
            actions: actions
        )
    }
}
