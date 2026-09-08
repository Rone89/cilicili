import SwiftUI

typealias DynamicCommentAvatar = CommentAvatar
typealias DynamicCommentMetricBadge = CommentMetricBadge

struct DynamicCommentImageGrid: View {
    @Environment(\.usesDynamicDetailCommentSpacing) private var usesRefinedSpacing

    let images: [DynamicImageItem]

    var body: some View {
        if usesRefinedSpacing && images.isEmpty {
            EmptyView()
        } else {
            CompactDynamicImageMosaicGrid(
                images: images,
                accessibilityName: "评论图片",
                placeholderFill: Color(.secondarySystemGroupedBackground)
            )
            .padding(.top, usesRefinedSpacing ? 0 : 2)
            .dynamicCommentHitArea(.control)
        }
    }
}

struct DynamicCommentInlineActionPill: View {
    @Environment(\.appThemeTintColor) private var appTintColor

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
        .foregroundStyle(appTintColor)
        .dynamicCommentHitArea(.control)
    }
}
