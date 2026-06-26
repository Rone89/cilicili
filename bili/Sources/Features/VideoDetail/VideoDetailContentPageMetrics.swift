import Foundation

enum VideoDetailContentPageMetrics {
    static let commentsTopPadding: CGFloat = 4
    static let horizontalPadding: CGFloat = 12
    static let spacing: CGFloat = 10
    static let topPadding: CGFloat = 8

    static func contentWidth(for layoutWidth: CGFloat) -> CGFloat {
        max(layoutWidth - horizontalPadding * 2, 0)
    }
}
