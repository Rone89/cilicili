import SwiftUI

struct ReplyPreviewRow: View {
    @AppStorage(CommentInteractionSettings.longPressActionsEnabledKey)
    private var longPressCommentActionsEnabled = false
    let reply: Comment
    let replyToComment: ((Comment) -> Void)?
    let showReplies: () -> Void

    init(
        reply: Comment,
        replyToComment: ((Comment) -> Void)? = nil,
        showReplies: @escaping () -> Void
    ) {
        self.reply = reply
        self.replyToComment = replyToComment
        self.showReplies = showReplies
    }

    var body: some View {
        BiliEmoteText(
            content: reply.content,
            font: .caption,
            textColor: .primary,
            emoteSize: 18,
            leadingName: reply.member?.uname ?? "Unknown",
            leadingNameColor: .secondary,
            showsLinkButtons: false,
            typographyRole: .metadata,
            onNonLinkTap: commentTapAction
        )
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .commentActionsMenu(
                longPressEnabled: longPressCommentActionsEnabled,
                text: reply.content?.message,
                copyTitle: "复制评论",
                replyAction: replyAction
            )
    }

    private var replyAction: (() -> Void)? {
        replyToComment.map { action in { action(reply) } }
    }

    private var commentTapAction: () -> Void {
        showReplies
    }
}
