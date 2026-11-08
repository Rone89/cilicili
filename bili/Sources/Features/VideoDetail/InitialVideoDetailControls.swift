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
    let contentWidth: CGFloat

    var body: some View {
        HStack(spacing: layout.actionSpacing) {
            avatarPlaceholder
                .frame(width: layout.avatarColumnWidth, height: layout.rowHeight)
                .padding(.trailing, layout.avatarActionSpacing - layout.actionSpacing)

            ForEach(0..<4, id: \.self) { _ in
                iconPlaceholder
                    .frame(width: layout.columnWidth, height: layout.rowHeight)
            }
        }
        .frame(
            width: contentWidth,
            height: layout.rowHeight,
            alignment: .leading
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

    private var iconPlaceholder: some View {
        Circle()
            .fill(VideoDetailTheme.secondarySurface.opacity(VideoDetailSkeletonStyle.actionStripFillOpacity))
            .frame(
                width: layout.actionLabelSide,
                height: layout.actionLabelSide
            )
    }

    private var layout: VideoDetailActionStripLayout {
        VideoDetailActionStripLayout(contentWidth: contentWidth)
    }
}
