import SwiftUI

typealias DynamicCommentAvatar = CommentAvatar
typealias DynamicCommentMetricBadge = CommentMetricBadge

struct DynamicCommentImageGrid: View {
    let images: [DynamicImageItem]

    var body: some View {
        CompactDynamicImageMosaicGrid(
            images: images,
            accessibilityName: "评论图片",
            placeholderFill: Color(.secondarySystemGroupedBackground)
        )
        .padding(.top, 2)
    }
}

struct DynamicCommentInlineActionPill: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .padding(.horizontal, 9)
                .frame(height: 26)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.pink)
    }
}
