import SwiftUI

struct VideoDetailActionStrip: View, Equatable {
    enum Metrics {
        static let rowHeight: CGFloat = 44
        static let actionLabelSide: CGFloat = 32
        static let avatarImageSide: CGFloat = 44
        static let iconSize: CGFloat = 17
        static let avatarPixelSize = 112
    }

    let model: VideoDetailActionStripModel
    let onFollow: () -> Void
    let onLike: () -> Void
    let onCoin: () -> Void
    let onFavorite: () -> Void
    let onShareTap: () -> Void
    @Environment(\.videoDetailActionButtonStyle) private var actionButtonStyle

    static func == (lhs: VideoDetailActionStrip, rhs: VideoDetailActionStrip) -> Bool {
        lhs.model == rhs.model
    }

    var body: some View {
        let usesPlainStyle = actionButtonStyle.usesPlainStyle
        let layout = VideoDetailActionStripLayout(contentWidth: model.contentWidth)

        Group {
            if usesPlainStyle {
                VideoDetailActionStripButtonRow(
                    model: model,
                    layout: layout,
                    onFollow: onFollow,
                    onLike: onLike,
                    onCoin: onCoin,
                    onFavorite: onFavorite,
                    onShareTap: onShareTap,
                    usesPlainStyle: true
                )
            } else {
                GlassEffectContainer(spacing: layout.columnSpacing) {
                    VideoDetailActionStripButtonRow(
                        model: model,
                        layout: layout,
                        onFollow: onFollow,
                        onLike: onLike,
                        onCoin: onCoin,
                        onFavorite: onFavorite,
                        onShareTap: onShareTap,
                        usesPlainStyle: false
                    )
                }
            }
        }
        .frame(width: model.contentWidth, height: layout.rowHeight, alignment: .center)
    }
}
