import SwiftUI

struct VideoDetailPlaybackSceneContextBuilder {
    let proxy: GeometryProxy
    let fullscreenCoordinator: VideoDetailFullscreenCoordinator
    let runtimeSettings: VideoDetailRuntimeSettingsStore
    let bindings: VideoDetailPlaybackSceneBindings

    var context: VideoDetailPlaybackSceneContext {
        VideoDetailPlaybackSceneContext(
            layout: layout,
            hostState: hostState
        )
    }

    private var layout: VideoDetailPlaybackSceneLayout {
        VideoDetailPlaybackSceneLayout(
            proxy: proxy,
            fullscreenCoordinator: fullscreenCoordinator
        )
    }

    private var hostState: VideoDetailPlaybackSceneHostState {
        VideoDetailPlaybackSceneHostState(
            layout: layout,
            showsPerformanceOverlay: runtimeSettings.playerPerformanceOverlayEnabled,
            sheetState: bindings.sheetState
        )
    }
}
