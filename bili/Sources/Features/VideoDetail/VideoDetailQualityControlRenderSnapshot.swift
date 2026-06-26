import Foundation

struct VideoDetailQualityControlRenderSnapshot: Equatable {
    var qualityInlineButtonTitle = "清晰度"
    var qualityAccessoryButtonTitle = "清晰度"
    var qualityButtonSystemImage = "slider.horizontal.3"
    var qualityMenuItems: [VideoDetailPlaybackQualityMenuItem] = []
    var isSupplementingPlayQualities = false
    var isSwitchingPlayQuality = false

    init() {}

    init(playback: VideoDetailPlaybackRenderSnapshot) {
        qualityInlineButtonTitle = playback.qualityInlineButtonTitle
        qualityAccessoryButtonTitle = playback.qualityAccessoryButtonTitle
        qualityButtonSystemImage = playback.qualityButtonSystemImage
        qualityMenuItems = playback.qualityMenuItems
        isSupplementingPlayQualities = playback.isSupplementingPlayQualities
        isSwitchingPlayQuality = playback.isSwitchingPlayQuality
    }
}
