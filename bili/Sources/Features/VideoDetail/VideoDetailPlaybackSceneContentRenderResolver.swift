import SwiftUI

struct VideoDetailPlaybackSceneContentRenderResolver {
    let fullscreenCoordinator: VideoDetailFullscreenCoordinator
    let runtimeSettings: VideoDetailRuntimeSettingsStore
    let bindings: VideoDetailPlaybackSceneBindings

    func renderPack(for proxy: GeometryProxy) -> VideoDetailPlaybackSceneContentRenderPack {
        VideoDetailPlaybackSceneContentRenderPackBuilder(
            proxy: proxy,
            fullscreenCoordinator: fullscreenCoordinator,
            runtimeSettings: runtimeSettings,
            bindings: bindings
        )
        .renderPack
    }
}
