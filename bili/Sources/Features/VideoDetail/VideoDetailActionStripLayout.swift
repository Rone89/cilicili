import SwiftUI

/// Button style affects appearance only; both styles share the same compact action geometry.
struct VideoDetailActionStripLayout {
    let contentWidth: CGFloat

    var avatarActionSpacing: CGFloat { compactSpacingScale * 12 }
    var actionSpacing: CGFloat { compactSpacingScale * 6 }
    var contentGroupWidth: CGFloat {
        columnWidth * 5 + avatarActionSpacing + actionSpacing * 3
    }
    private var compactSpacingScale: CGFloat {
        min(max(contentWidth - columnWidth * 5, 0) / 30, 1)
    }
    var rowHeight: CGFloat { VideoDetailActionStrip.Metrics.rowHeight }
    var actionLabelSide: CGFloat { VideoDetailActionStrip.Metrics.actionLabelSide }
    var avatarImageSide: CGFloat { VideoDetailActionStrip.Metrics.avatarImageSide }
    var columnWidth: CGFloat { min(rowHeight, max(contentWidth / 5, 1)) }
    var avatarColumnWidth: CGFloat { columnWidth }
}
