import SwiftUI

/// Button style affects appearance only; both styles share the same five-column geometry.
struct VideoDetailActionStripLayout {
    let contentWidth: CGFloat

    var columnSpacing: CGFloat { max((contentWidth - columnWidth * 5) / 4, 0) }
    var rowHeight: CGFloat { VideoDetailActionStrip.Metrics.rowHeight }
    var actionLabelSide: CGFloat { VideoDetailActionStrip.Metrics.actionLabelSide }
    var avatarImageSide: CGFloat { VideoDetailActionStrip.Metrics.avatarImageSide }
    var columnWidth: CGFloat { min(rowHeight, max(contentWidth / 5, 1)) }
    var avatarColumnWidth: CGFloat { columnWidth }
}
