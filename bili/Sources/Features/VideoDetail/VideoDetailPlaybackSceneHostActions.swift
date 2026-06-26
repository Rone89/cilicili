import Foundation

@MainActor
struct VideoDetailPlaybackSceneHostActions {
    let playbackLoad: VideoDetailPlaybackScenePlaybackLoadActions

    func retryPlaybackLoad() {
        playbackLoad.retryPlaybackLoad()
    }
}
