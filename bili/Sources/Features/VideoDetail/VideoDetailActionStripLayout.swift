import SwiftUI

struct VideoDetailActionStripLayout {
    let contentWidth: CGFloat
    let usesPlainStyle: Bool

    init(contentWidth: CGFloat, usesPlainStyle: Bool = false) {
        self.contentWidth = contentWidth
        self.usesPlainStyle = usesPlainStyle
    }

    var columnSpacing: CGFloat {
        if usesPlainStyle {
            let fixedWidth = columnWidth * 5 + followColumnWidth
            let remainingWidth = contentWidth - fixedWidth
            return max(remainingWidth / 5, 0)
        }
        return VideoDetailActionStrip.Metrics.columnSpacing
    }

    var rowHeight: CGFloat {
        usesPlainStyle ? VideoDetailActionStrip.Metrics.plainRowHeight : VideoDetailActionStrip.Metrics.rowHeight
    }

    var actionLabelSide: CGFloat {
        usesPlainStyle
            ? VideoDetailActionStrip.Metrics.plainActionLabelSide : VideoDetailActionStrip.Metrics.actionLabelSide
    }

    var avatarImageSide: CGFloat {
        usesPlainStyle
            ? VideoDetailActionStrip.Metrics.plainAvatarImageSide : VideoDetailActionStrip.Metrics.avatarImageSide
    }

    var followHeight: CGFloat {
        usesPlainStyle ? VideoDetailActionStrip.Metrics.plainFollowHeight : VideoDetailActionStrip.Metrics.followHeight
    }

    var columnWidth: CGFloat {
        if usesPlainStyle {
            return min(VideoDetailActionStrip.Metrics.plainRowHeight, max(contentWidth, 1))
        }
        return max((contentWidth - columnSpacing * 5) / 6, 1)
    }

    var avatarColumnWidth: CGFloat { columnWidth }

    var followColumnWidth: CGFloat {
        usesPlainStyle ? VideoDetailActionStrip.Metrics.plainFollowColumnWidth : columnWidth
    }
}
