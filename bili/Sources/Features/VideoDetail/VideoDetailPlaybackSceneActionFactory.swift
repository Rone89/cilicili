import Foundation

@MainActor
struct VideoDetailPlaybackSceneActionFactory {
    let dependencies: VideoDetailPlaybackSceneActionDependencies
    let closeCallbacks: VideoDetailPlaybackSceneCloseCallbacks
    let sheetCallbacks: VideoDetailPlaybackSceneSheetCallbacks

    var actions: VideoDetailPlaybackSceneActions {
        VideoDetailPlaybackSceneActionGraph(
            dependencies: dependencies,
            closeCallbacks: closeCallbacks,
            sheetCallbacks: sheetCallbacks
        ).actions
    }
}
