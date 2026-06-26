import Foundation

struct VideoDetailPlayerSurfaceRenderSnapshot: Equatable {
    var historyVideo: VideoItem?
    var historyCID: Int?
    var duration: TimeInterval?
    var isDanmakuEnabled = true

    init() {}

    init(playback: VideoDetailPlaybackRenderSnapshot) {
        historyVideo = playback.historyVideo
        historyCID = playback.historyCID
        duration = playback.duration
        isDanmakuEnabled = playback.isDanmakuEnabled
    }
}
