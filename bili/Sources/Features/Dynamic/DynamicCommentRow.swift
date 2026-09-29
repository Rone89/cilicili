import SwiftUI

struct DynamicCommentRow: View {
    @AppStorage(CommentInteractionSettings.longPressActionsEnabledKey)
    private var longPressCommentActionsEnabled = false
    let item: DynamicCommentRowItem
    let showReplies: () -> Void
    let replyToComment: ((Comment, Comment) -> Void)?

    private var comment: Comment {
        item.comment
    }

    private var display: DynamicCommentRowDisplayModel {
        item.display
    }

    init(
        item: DynamicCommentRowItem,
        showReplies: @escaping () -> Void,
        replyToComment: ((Comment, Comment) -> Void)? = nil
    ) {
        self.item = item
        self.showReplies = showReplies
        self.replyToComment = replyToComment
    }

    var body: some View {
        sharedCommentLayout
    }

    private var replyAction: (() -> Void)? {
        guard let replyToComment else { return nil }
        return { replyToComment(comment, comment) }
    }

    private var contentReplyAction: (() -> Void)? {
        if let replyAction {
            guard !longPressCommentActionsEnabled else { return nil }
            return replyAction
        }
        return showReplies
    }

    private var sharedCommentLayout: some View {
        CommentRowLayout(
            fullRowReplyAction: contentReplyAction,
            fullRowReplyAccessibilityLabel: "回复 \(display.authorName) 的评论"
        ) {
            DynamicCommentAvatar(
                urlString: display.avatarURLString,
                owner: display.authorOwner,
                size: 38
            )
        } header: {
            DynamicCommentRowHeader(
                comment: comment,
                display: display
            )
        } bodyContent: {
            DynamicCommentText(
                content: comment.content,
                font: .subheadline,
                textColor: .primary,
                emoteSize: 21,
                lineSpacing: 1,
                typographyRole: .commentBody,
                onNonLinkTap: contentReplyAction
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        } media: {
            DynamicCommentImageGrid(images: display.pictures)
        } reply: {
            if display.visibleReplyCount > 0 {
                CommentReplyPreviewContainer(
                    replyCount: display.visibleReplyCount,
                    showsPreview: !display.replyPreviews.isEmpty,
                    showReplies: showReplies
                ) {
                    ForEach(display.replyPreviews) { reply in
                        DynamicReplyPreviewRow(
                            reply: reply,
                            replyAction: replyToComment.map { action in
                                { action(comment, reply) }
                            },
                            showReplies: showReplies
                        )
                    }
                }
                .dynamicCommentHitArea(.control)
            }
        }
        .commentActionsMenu(
            longPressEnabled: longPressCommentActionsEnabled,
            text: comment.content?.message,
            copyTitle: "复制评论",
            replyAction: replyAction
        )
    }
}
