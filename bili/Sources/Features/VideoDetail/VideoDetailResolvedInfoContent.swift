import SwiftUI

struct VideoDetailResolvedInfoContent: View {
    @ObservedObject var store: VideoDetailDescriptionRenderStore
    @Binding var isExpanded: Bool

    private var presentation: VideoDetailInfoPresentation {
        VideoDetailInfoPresentation(store: store, isExpanded: isExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            titleRow
                .commentCopyContextMenu(text: store.titleText, title: "复制标题")

            VideoDetailInfoMetadataRow(
                metadataText: presentation.metadataText,
                descriptionCopyText: presentation.hasDescriptionContent && !isExpanded ? presentation.descriptionText : nil
            )

            if isExpanded && presentation.hasDescriptionContent {
                VideoDetailExpandedDescriptionText(descriptionText: presentation.descriptionText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy(duration: 0.22), value: isExpanded)
    }

    @ViewBuilder
    private var titleRow: some View {
        if presentation.hasDescriptionContent || presentation.titleText.contains(where: \.isNewline) {
            expandableTitle
        } else {
            ViewThatFits(in: .horizontal) {
                VideoDetailInfoTitleText(text: presentation.titleText, isExpanded: false)
                    .fixedSize(horizontal: true, vertical: false)

                expandableTitle
            }
        }
    }

    private var expandableTitle: some View {
        HStack(alignment: .top, spacing: 6) {
            VideoDetailInfoTitleText(text: presentation.titleText, isExpanded: isExpanded)

            Button(action: toggleExpansion) {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(isExpanded ? "收起视频详情" : "展开视频详情")
        }
    }

    private func toggleExpansion() {
        withAnimation(.snappy(duration: 0.22)) {
            isExpanded.toggle()
        }
    }
}
