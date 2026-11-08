import SwiftUI

/// Button style affects appearance only; both styles share the same compact action geometry.
struct VideoDetailActionStripLayout {
    private static let preferredAvatarGap: CGFloat = 20
    private static let preferredActionGap: CGFloat = 12

    let contentWidth: CGFloat

    var avatarActionSpacing: CGFloat { compactSpacingScale * Self.preferredAvatarGap }
    var actionSpacing: CGFloat { compactSpacingScale * Self.preferredActionGap }
    var contentGroupWidth: CGFloat {
        columnWidth * 5 + avatarActionSpacing + actionSpacing * 3
    }
    private var compactSpacingScale: CGFloat {
        let preferredSpacing = Self.preferredAvatarGap + Self.preferredActionGap * 3
        return min(max(contentWidth - columnWidth * 5, 0) / preferredSpacing, 1)
    }
    var rowHeight: CGFloat { VideoDetailActionStrip.Metrics.rowHeight }
    var actionLabelSide: CGFloat { VideoDetailActionStrip.Metrics.actionLabelSide }
    var avatarImageSide: CGFloat { VideoDetailActionStrip.Metrics.avatarImageSide }
    var columnWidth: CGFloat { min(rowHeight, max(contentWidth / 5, 1)) }
    var avatarColumnWidth: CGFloat { columnWidth }
}
