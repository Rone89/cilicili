import SwiftUI

struct DynamicCommentRowContent: View {
    let comment: Comment
    let display: DynamicCommentRowDisplayModel
    let showReplies: () -> Void
    let replyToComment: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DynamicCommentRowHeader(comment: comment, display: display)

            DynamicCommentText(
                content: comment.content,
                font: .subheadline,
                textColor: .primary,
                emoteSize: 21,
                lineSpacing: 1,
                typographyRole: .commentBody
            )
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                replyToComment?()
            }
            .accessibilityHint(replyToComment == nil ? "" : "轻点以回复")

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

struct DynamicCommentRowHeader: View {
    let comment: Comment
    let display: DynamicCommentRowDisplayModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            CommentAuthorIdentity(name: display.authorName, owner: display.authorOwner)
                .foregroundStyle(.primary)

            if !display.timeText.isEmpty {
                Text(display.timeText)
                    .appTypography(.metadata, fallback: .caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            CommentLikeButton(comment: comment)
        }
    }
}

struct DynamicCommentReplyPreviewButton: View {
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
