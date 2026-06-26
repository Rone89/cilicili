import SwiftUI

struct VideoDetailPlaybackSceneContentRenderPackBuilder {
    let proxy: GeometryProxy
    let fullscreenCoordinator: VideoDetailFullscreenCoordinator
    let runtimeSettings: VideoDetailRuntimeSettingsStore
    let bindings: VideoDetailPlaybackSceneBindings

    var renderPack: VideoDetailPlaybackSceneContentRenderPack {
        let context = context
        return VideoDetailPlaybackSceneContentRenderPack(
            context: context,
            standardPlaybackConfig: standardPlaybackConfig(layout: context.layout)
        )
    }

    private var context: VideoDetailPlaybackSceneContext {
        VideoDetailPlaybackSceneContextBuilder(
            proxy: proxy,
            fullscreenCoordinator: fullscreenCoordinator,
            runtimeSettings: runtimeSettings,
            bindings: bindings
        )
        .context
    }

    private func standardPlaybackConfig(
        layout: VideoDetailPlaybackSceneLayout
    ) -> VideoDetailStandardPlaybackContainerConfig {
        VideoDetailStandardPlaybackContainerConfigBuilder(
            layout: layout,
            fullscreenCoordinator: fullscreenCoordinator,
            isShowingDanmakuSettings: bindings.isShowingDanmakuSettings.wrappedValue,
            runtimeSettings: runtimeSettings
        )
        .config
    }
}
