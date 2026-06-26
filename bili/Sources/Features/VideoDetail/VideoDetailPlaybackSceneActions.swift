import Foundation

@MainActor
struct VideoDetailPlaybackSceneActions {
    let standardPlayback: VideoDetailStandardPlaybackActions
    let fullscreen: VideoDetailPlaybackSceneFullscreenActions
    let lifecycle: VideoDetailPlaybackSceneLifecycleActions
}
