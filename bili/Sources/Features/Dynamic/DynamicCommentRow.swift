import SwiftUI

struct DynamicCommentRow: View {
    @Environment(\.usesDynamicDetailCommentRowLayout) private var usesSharedCommentLayout

    let item: DynamicCommentRowItem
    let showReplies: () -> Void
    let replyToComment: (() -> Void)?

    private var comment: Comment {
        item.comment
    }

    private var display: DynamicCommentRowDisplayModel {
        item.display
    }

    init(
        item: DynamicCommentRowItem,
        showReplies: @escaping () -> Void,
        replyToComment: (() -> Void)? = nil
    ) {
        self.item = item
        self.showReplies = showReplies
        self.replyToComment = replyToComment
    }

    var body: some View {
        Group {
            if usesSharedCommentLayout {
            sharedCommentLayout
            } else {
                legacyCommentLayout
            }
        }
    }

    private var contentReplyAction: () -> Void {
        {
            if let replyToComment {
                replyToComment()
            } else {
                showReplies()
            }
        }
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
                typographyRole: .commentBody
            )
            .frame(
                maxWidth: .infinity,
                minHeight: 44,
                alignment: .leading
            )
        } media: {
            DynamicCommentImageGrid(images: display.pictures)
        } reply: {
            if display.visibleReplyCount > 0 {
                Button(action: showReplies) {
                    CommentReplyPreviewContainer(
                        replyCount: display.visibleReplyCount,
                        showsPreview: !display.replyPreviews.isEmpty
                    ) {
                        ForEach(display.replyPreviews) { reply in
                            DynamicReplyPreviewRow(reply: reply)
                        }
                    }
                }
                .buttonStyle(.plain)
                .dynamicCommentHitArea(.control)
            }
        }
    }

    private var legacyCommentLayout: some View {
        DynamicCommentFullRowReplyTarget(
            action: contentReplyAction,
            accessibilityLabel: "回复 \(display.authorName) 的评论"
        ) {
            HStack(alignment: .top, spacing: 10) {
                DynamicCommentAvatar(
                    urlString: display.avatarURLString,
                    owner: display.authorOwner,
                    size: 38
                )

                DynamicCommentRowContent(
                    comment: comment,
                    display: display,
                    showReplies: showReplies
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            }
            .padding(.vertical, 10)
        }
    }
}
