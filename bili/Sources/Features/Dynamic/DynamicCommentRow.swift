import SwiftUI

struct DynamicCommentRow: View {
    @Environment(\.usesDynamicDetailCommentRowLayout) private var usesSharedCommentLayout

    let item: DynamicCommentRowItem
    let showReplies: () -> Void
    let enablesSwipeReply: Bool
    let enablesExpandedReplyTap: Bool
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
        enablesExpandedReplyTap: Bool = false,
        replyToComment: (() -> Void)? = nil
    ) {
        self.item = item
        self.showReplies = showReplies
        self.enablesSwipeReply = enablesSwipeReply
        self.enablesExpandedReplyTap = enablesExpandedReplyTap
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
            action: triggerSwipeReply
        ))
    }

    private var contentReplyAction: (() -> Void)? {
        enablesExpandedReplyTap ? performReply : replyToComment
    }

    private func performReply() {
        if let replyToComment {
            replyToComment()
        } else {
            showReplies()
        }
    }

    private func triggerSwipeReply() {
        Haptics.light()
        performReply()
    }

    private var sharedCommentLayout: some View {
        CommentRowLayout(
            fullRowReplyAction: enablesExpandedReplyTap ? contentReplyAction : nil,
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
                display: display,
                replyAction: contentReplyAction,
                showsReplyTapArea: enablesExpandedReplyTap && contentReplyAction != nil,
                usesFullRowReplyTarget: enablesExpandedReplyTap
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
                minHeight: enablesExpandedReplyTap && contentReplyAction != nil ? 44 : nil,
                alignment: .leading
            )
            .contentShape(Rectangle())
            .dynamicCommentDirectReply(
                isEnabled: !enablesExpandedReplyTap && contentReplyAction != nil
            ) {
                contentReplyAction?()
            }
            .dynamicCommentReplyTapArea(
                isEnabled: enablesExpandedReplyTap && contentReplyAction != nil
            )
            .accessibilityHint(contentReplyAction == nil ? "" : "轻点以回复")
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
        DynamicCommentFullRowReplyTarget(
            action: enablesExpandedReplyTap ? contentReplyAction : nil,
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
                    showReplies: showReplies,
                    replyToComment: replyToComment,
                    replyAction: contentReplyAction,
                    showsReplyTapArea: enablesExpandedReplyTap && contentReplyAction != nil,
                    usesFullRowReplyTarget: enablesExpandedReplyTap
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            }
            .padding(.vertical, 10)
        }
    }
}

private struct DynamicCommentReplyTapAreaModifier: ViewModifier {
    @Environment(\.appThemeTintColor) private var appTintColor
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        content.background {
            if isEnabled {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(appTintColor.opacity(0.12))
                    .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    @ViewBuilder
    func dynamicCommentDirectReply(
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        if isEnabled {
            onTapGesture(perform: action)
        } else {
            self
        }
    }

    func dynamicCommentReplyTapArea(isEnabled: Bool) -> some View {
        modifier(DynamicCommentReplyTapAreaModifier(isEnabled: isEnabled))
    }
}

struct DynamicCommentSwipeReplyModifier: ViewModifier {
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
