import SwiftUI

struct DynamicCommentRowContent: View {
    let comment: Comment
    let display: DynamicCommentRowDisplayModel
    let showReplies: () -> Void
    let replyToComment: (() -> Void)?
    let replyAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DynamicCommentRowHeader(
                comment: comment,
                display: display,
                replyAction: replyAction
            )

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
            .onTapGesture { (replyAction ?? replyToComment)?() }
            .accessibilityHint((replyAction ?? replyToComment) == nil ? "" : "轻点以回复")

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
    let replyAction: (() -> Void)?

    init(
        comment: Comment,
        display: DynamicCommentRowDisplayModel,
        replyAction: (() -> Void)? = nil
    ) {
        self.comment = comment
        self.display = display
        self.replyAction = replyAction
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                CommentAuthorIdentity(name: display.authorName, owner: display.authorOwner)
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                if !display.timeText.isEmpty {
                    Text(display.timeText)
                        .appTypography(.metadata, fallback: .caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 38, alignment: .top)
            .contentShape(Rectangle())
            .onTapGesture { replyAction?() }

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
