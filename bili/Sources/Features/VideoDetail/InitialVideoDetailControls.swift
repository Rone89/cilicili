import SwiftUI

struct InitialVideoDetailControls: View {
    let titleText: String
    let contentWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VideoDetailInfoLoadingPlaceholder(titleText: titleText)
            InitialVideoDetailActionStrip(contentWidth: contentWidth)
        }
        .frame(width: contentWidth, alignment: .leading)
        .allowsHitTesting(false)
    }
}

private struct InitialVideoDetailActionStrip: View {
    @Environment(\.videoDetailActionButtonStyle) private var actionButtonStyle
    let contentWidth: CGFloat

    var body: some View {
        let usesPlainStyle = actionButtonStyle.usesPlainStyle
        HStack(spacing: layout.columnSpacing) {
            avatarPlaceholder
                .frame(width: layout.avatarColumnWidth, height: layout.rowHeight)

            followPlaceholder
                .frame(width: layout.followColumnWidth, height: layout.rowHeight)

            ForEach(0..<4, id: \.self) { _ in
                iconPlaceholder
                    .frame(width: layout.columnWidth, height: layout.rowHeight)
            }
        }
        .frame(
            width: contentWidth,
            height: layout.rowHeight,
            alignment: .center
        )
        .accessibilityHidden(true)
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(VideoDetailTheme.secondarySurface.opacity(VideoDetailSkeletonStyle.actionStripFillOpacity))
            .frame(
                width: layout.avatarImageSide,
                height: layout.avatarImageSide
            )
    }

    private var followPlaceholder: some View {
        Capsule(style: .continuous)
            .fill(VideoDetailTheme.secondarySurface.opacity(VideoDetailSkeletonStyle.actionStripFillOpacity))
            .frame(height: layout.followHeight)
    }

    private var iconPlaceholder: some View {
        Circle()
            .fill(VideoDetailTheme.secondarySurface.opacity(VideoDetailSkeletonStyle.actionStripFillOpacity))
            .frame(
                width: layout.actionLabelSide,
                height: layout.actionLabelSide
            )
    }

    private var layout: VideoDetailActionStripLayout {
        VideoDetailActionStripLayout(
            contentWidth: contentWidth,
            usesPlainStyle: actionButtonStyle.usesPlainStyle
        )
    }
}
