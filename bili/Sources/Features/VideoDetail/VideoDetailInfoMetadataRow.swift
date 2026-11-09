import SwiftUI

struct VideoDetailInfoMetadataRow: View {
    let metadataText: String
    let descriptionCopyText: String?

    var body: some View {
        Text(metadataText)
            .appTypography(.metadata, fallback: .caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(height: 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .commentCopyContextMenu(text: descriptionCopyText, title: "复制简介")
    }
}
