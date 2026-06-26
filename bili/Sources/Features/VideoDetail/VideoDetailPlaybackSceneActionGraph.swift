import Foundation

@MainActor
struct VideoDetailPlaybackSceneActionGraph {
    let fullscreen: VideoDetailPlaybackSceneFullscreenActions
    let sheets: VideoDetailPlaybackSceneSheetActions
    let close: VideoDetailPlaybackSceneCloseActions
    let lifecycle: VideoDetailPlaybackSceneLifecycleActions
    let standardPlayback: VideoDetailStandardPlaybackActions

    init(
        dependencies: VideoDetailPlaybackSceneActionDependencies,
        closeCallbacks: VideoDetailPlaybackSceneCloseCallbacks,
        sheetCallbacks: VideoDetailPlaybackSceneSheetCallbacks
    ) {
        let components = VideoDetailPlaybackSceneActionGraphBuilder(
            dependencies: dependencies,
            closeCallbacks: closeCallbacks,
            sheetCallbacks: sheetCallbacks
        ).components

        fullscreen = components.fullscreen
        sheets = components.sheets
        close = components.close
        lifecycle = components.lifecycle
        standardPlayback = components.standardPlayback
    }

    var actions: VideoDetailPlaybackSceneActions {
        VideoDetailPlaybackSceneActions(
            standardPlayback: standardPlayback,
            fullscreen: fullscreen,
            lifecycle: lifecycle
        )
    }
}
