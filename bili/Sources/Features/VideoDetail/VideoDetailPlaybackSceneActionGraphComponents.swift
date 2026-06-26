import Foundation

@MainActor
struct VideoDetailPlaybackSceneActionGraphComponents {
    let fullscreen: VideoDetailPlaybackSceneFullscreenActions
    let sheets: VideoDetailPlaybackSceneSheetActions
    let close: VideoDetailPlaybackSceneCloseActions
    let lifecycle: VideoDetailPlaybackSceneLifecycleActions
    let standardPlayback: VideoDetailStandardPlaybackActions
}
