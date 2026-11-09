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
                hasDescriptionContent: presentation.hasDescriptionContent,
                isExpanded: isExpanded,
                descriptionCopyText: presentation.hasDescriptionContent && !isExpanded ? presentation.descriptionText : nil,
                toggleExpansion: toggleExpansion
            )

            if isExpanded && presentation.hasDescriptionContent {
                VideoDetailExpandedDescriptionText(descriptionText: presentation.descriptionText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy(duration: 0.22), value: isExpanded)
    }

    private var titleRow: some View {
        ViewThatFits(in: .horizontal) {
            VideoDetailInfoTitleText(text: presentation.titleText, isExpanded: false)
                .fixedSize(horizontal: true, vertical: false)

            Button(action: toggleExpansion) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    VideoDetailInfoTitleText(text: presentation.titleText, isExpanded: isExpanded)

                    Text(isExpanded ? "收起" : "展开")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(presentation.titleText)
            .accessibilityHint(isExpanded ? "收起视频标题" : "展开视频标题")
        }
    }

    private func toggleExpansion() {
        withAnimation(.snappy(duration: 0.22)) {
            isExpanded.toggle()
        }
    }
}
