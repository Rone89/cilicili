import Foundation

struct VideoDetailStandardPlaybackRenderContext {
    let selectedPlayVariant: PlayVariant?
    let selectedCID: Int?
    let pages: [VideoPage]
    let qualityMenuItems: [VideoDetailPlaybackQualityMenuItem]

    var isPortraitVideo: Bool {
        currentVideoAspectRatio.map { $0 < 0.9 } ?? false
    }

    private var currentVideoAspectRatio: Double? {
        selectedPlayVariant?.videoAspectRatio
            ?? selectedPage?.dimension?.aspectRatio
            ?? qualityMenuItems.compactMap { $0.variant.videoAspectRatio }.first
    }

    private var selectedPage: VideoPage? {
        guard let selectedCID else { return nil }
        return pages.first { $0.cid == selectedCID }
    }
}
