import SwiftUI

struct VideoDetailStandardPlaybackScrollState {
    private var offsets: [VideoDetailContentTab: CGFloat] = [:]

    func offset(for tab: VideoDetailContentTab) -> CGFloat {
        offsets[tab, default: 0]
    }

    mutating func update(tab: VideoDetailContentTab, offset: CGFloat) {
        let normalizedOffset = max(0, offset)
        guard abs(offsets[tab, default: 0] - normalizedOffset) > 0.5 else { return }
        offsets[tab] = normalizedOffset
    }

    mutating func reset() {
        offsets = [:]
    }
}
