import SwiftUI

struct CommentRow: View, Equatable {
    @AppStorage(CommentInteractionSettings.longPressActionsEnabledKey)
    private var longPressCommentActionsEnabled = false
    let item: VideoDetailCommentDisplayItem
    let style: CommentSectionStyle
    let showReplies: () -> Void
    let replyToComment: ((Comment) -> Void)?

    private var comment: Comment { item.comment }
    private var display: VideoDetailCommentDisplayModel { item.display }

    init(
        item: VideoDetailCommentDisplayItem,
        style: CommentSectionStyle,
        showReplies: @escaping () -> Void,
        replyToComment: ((Comment) -> Void)? = nil
    ) {
        self.item = item
        self.style = style
        self.showReplies = showReplies
        self.replyToComment = replyToComment
    }

    static func == (lhs: CommentRow, rhs: CommentRow) -> Bool {
        lhs.item == rhs.item
            && lhs.style == rhs.style
            && lhs.longPressCommentActionsEnabled == rhs.longPressCommentActionsEnabled
            && (lhs.replyToComment != nil) == (rhs.replyToComment != nil)
    }

    var body: some View {
        CommentRowLayout(
            fullRowReplyAction: commentTapAction,
            fullRowReplyAccessibilityLabel: "回复 \(display.authorName) 的评论"
        ) {
            CommentAvatar(
                urlString: display.avatarURLString,
                owner: display.authorOwner,
                size: 38
            )
        } header: {
            CommentRowHeader(comment: comment, display: display)
        } bodyContent: {
            BiliEmoteText(
                content: comment.content,
                font: .subheadline,
                textColor: .primary,
                emoteSize: 21,
                typographyRole: .commentBody,
                onNonLinkTap: commentTapAction
            )
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
        } media: {
            CommentImageButton(
                images: display.pictures,
                transitionScope: comment.id.description
            )
        } reply: {
            CommentRowReplyPreviewSection(
                display: display,
                isEnabled: style.showsReplyPreviewContainer,
                showReplies: showReplies,
                replyToComment: replyToComment
            )
        }
        .commentActionsMenu(
            longPressEnabled: longPressCommentActionsEnabled,
            text: comment.content?.message,
            copyTitle: "复制评论",
            replyAction: replyAction
        )
    }

    private var commentTapAction: (() -> Void)? {
        guard !longPressCommentActionsEnabled, let replyAction else { return nil }
        return replyAction
    }

    private var replyAction: (() -> Void)? {
        replyToComment.map { action in { action(comment) } }
    }
}
