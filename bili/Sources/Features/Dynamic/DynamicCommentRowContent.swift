import SwiftUI

struct DynamicCommentRowContent: View {
    let comment: Comment
    let display: DynamicCommentRowDisplayModel
    let showReplies: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DynamicCommentRowHeader(display: display)

            DynamicCommentText(
                content: comment.content,
                font: .subheadline,
                textColor: .primary,
                emoteSize: 21,
                lineSpacing: 1
            )

            DynamicCommentImageGrid(images: display.pictures)

            DynamicCommentReplyPreviewButton(
                replies: display.replyPreviews,
                showReplies: showReplies
            )

            if display.visibleReplyCount > 0 {
                DynamicCommentInlineActionPill(
                    title: "\(display.visibleReplyCount) 条回复",
                    systemImage: "bubble.left.and.bubble.right",
                    action: showReplies
                )
                .padding(.top, 1)
            }
        }
    }
}

private struct DynamicCommentRowHeader: View {
    let display: DynamicCommentRowDisplayModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(display.authorName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            if !display.timeText.isEmpty {
                Text(display.timeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            DynamicCommentMetricBadge(
                text: display.likeText,
                systemImage: display.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup",
                isHighlighted: display.isLiked
            )
        }
    }
}

private struct DynamicCommentReplyPreviewButton: View {
    let replies: [Comment]
    let showReplies: () -> Void

    var body: some View {
        if !replies.isEmpty {
            Button(action: showReplies) {
                DynamicCommentReplyPreviewContainer {
                    ForEach(replies) { reply in
                        DynamicReplyPreviewRow(reply: reply)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}
