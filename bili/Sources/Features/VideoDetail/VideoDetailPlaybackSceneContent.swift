import SwiftUI

struct VideoDetailPlaybackSceneContent: View {
    @ObservedObject var viewModel: VideoDetailViewModel
    @ObservedObject var fullscreenCoordinator: VideoDetailFullscreenCoordinator
    @ObservedObject var runtimeSettings: VideoDetailRuntimeSettingsStore
    @ObservedObject var libraryStore: LibraryStore
    let scenePhase: ScenePhase
    let bindings: VideoDetailPlaybackSceneBindings
    let actions: VideoDetailPlaybackSceneActions

    var body: some View {
        GeometryReader { proxy in
            VideoDetailPlaybackSceneResolvedContent(
                viewModel: viewModel,
                fullscreenCoordinator: fullscreenCoordinator,
                libraryStore: libraryStore,
                scenePhase: scenePhase,
                proxySize: proxy.size,
                renderPack: renderResolver.renderPack(for: proxy),
                bindings: bindings,
                actions: actions
            )
        }
    }

    private var renderResolver: VideoDetailPlaybackSceneContentRenderResolver {
        VideoDetailPlaybackSceneContentRenderResolver(
            fullscreenCoordinator: fullscreenCoordinator,
            runtimeSettings: runtimeSettings,
            bindings: bindings
        )
    }
}
