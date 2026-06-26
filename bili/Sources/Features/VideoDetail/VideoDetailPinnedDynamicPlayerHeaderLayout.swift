import SwiftUI

struct VideoDetailPinnedDynamicPlayerHeaderLayout: Equatable {
    let screenSize: CGSize
    let standardHeight: CGFloat
    let isPortraitVideo: Bool
    let isEnabled: Bool

    private let collapsedToolbarHeight: CGFloat = 58

    var expandedHeight: CGFloat {
        guard isEnabled, isPortraitVideo else { return standardHeight }
        let proposedHeight = max(screenSize.height * 0.65, screenSize.width)
        let maximumHeight = max(standardHeight, screenSize.height * 0.72)
        return max(standardHeight, min(proposedHeight, maximumHeight))
    }

    func playerHeight(
        fallbackHeight: CGFloat,
        scrollOffset: CGFloat,
        isPlaybackActive: Bool
    ) -> CGFloat {
        guard isEnabled else { return fallbackHeight }
        let minimumHeight = isPlaybackActive ? standardHeight : collapsedToolbarHeight
        return max(expandedHeight - max(0, scrollOffset), minimumHeight)
    }

    func usesCollapsedChrome(playerHeight: CGFloat, isPlaybackActive: Bool) -> Bool {
        guard isEnabled, !isPlaybackActive else { return false }
        return playerHeight < standardHeight - 4
    }
}
