import SwiftUI

struct DynamicCommentRow: View {
    @Environment(\.usesDynamicDetailCommentRowLayout) private var usesSharedCommentLayout

    let item: DynamicCommentRowItem
    let showReplies: () -> Void
    let enablesSwipeReply: Bool
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
        enablesSwipeReply: Bool = false,
        replyToComment: (() -> Void)? = nil
    ) {
        self.item = item
        self.showReplies = showReplies
        self.enablesSwipeReply = enablesSwipeReply
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
        .modifier(DynamicCommentSwipeReplyModifier(
            isEnabled: enablesSwipeReply,
            action: replyAction
        ))
    }

    private func replyAction() {
        if let replyToComment {
            replyToComment()
        } else {
            showReplies()
        }
    }

    private var sharedCommentLayout: some View {
        CommentRowLayout {
            DynamicCommentAvatar(
                urlString: display.avatarURLString,
                owner: display.authorOwner,
                size: 38
            )
        } header: {
            DynamicCommentRowHeader(comment: comment, display: display)
        } bodyContent: {
            DynamicCommentText(
                content: comment.content,
                font: .subheadline,
                textColor: .primary,
                emoteSize: 21,
                lineSpacing: 1,
                typographyRole: .commentBody
            )
            .contentShape(Rectangle())
            .onTapGesture { replyToComment?() }
            .accessibilityHint(replyToComment == nil ? "" : "轻点以回复")
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
            }
        }
    }

    private var legacyCommentLayout: some View {
        HStack(alignment: .top, spacing: 10) {
            DynamicCommentAvatar(
                urlString: display.avatarURLString,
                owner: display.authorOwner,
                size: 38
            )

            DynamicCommentRowContent(
                comment: comment,
                display: display,
                showReplies: showReplies,
                replyToComment: replyToComment
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
        }
        .padding(.vertical, 10)
    }
}

private struct DynamicCommentSwipeReplyModifier: ViewModifier {
    let isEnabled: Bool
    let action: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(action: action) {
                        Label("回复", systemImage: "arrowshape.turn.up.left")
                    }
                    .tint(.accentColor)
                }
        } else {
            content
        }
    }
}
