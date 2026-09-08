import SwiftUI

struct CommentReplyDetailRow: View {
    @Environment(\.appThemeTintColor) private var appTintColor
    @Environment(\.usesDynamicDetailCommentSpacing) private var usesRefinedSpacing

    let item: VideoDetailCommentReplyDisplayItem
    let showDialog: (() -> Void)?

    private var reply: Comment { item.reply }
    private var display: VideoDetailCommentDisplayModel { item.display }

    init(item: VideoDetailCommentReplyDisplayItem, showDialog: (() -> Void)?) {
        self.item = item
        self.showDialog = showDialog
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CommentAvatar(
                urlString: display.avatarURLString,
                owner: display.authorOwner,
                size: 36
            )

            VStack(alignment: .leading, spacing: usesRefinedSpacing ? 0 : 8) {
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        CommentAuthorIdentity(name: display.authorName, owner: display.authorOwner)
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 0)

                        if !display.timeText.isEmpty {
                            Text(display.timeText)
                                .appTypography(.metadata, fallback: .caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(minHeight: 36, alignment: .top)

                    Spacer(minLength: 8)

                    CommentLikeButton(comment: reply)
                }

                BiliEmoteText(
                    content: reply.content,
                    font: .subheadline,
                    textColor: .primary,
                    emoteSize: 22,
                    typographyRole: .commentBody
                )
                    .padding(.top, usesRefinedSpacing ? 4 : 0)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)

                if usesRefinedSpacing {
                    if !display.pictures.isEmpty {
                        CommentImageButton(
                            images: display.pictures,
                            transitionScope: reply.id.description
                        )
                        .padding(.top, 8)
                    }
                } else {
                    CommentImageButton(
                        images: display.pictures,
                        transitionScope: reply.id.description
                    )
                }

                if let showDialog {
                    Button(action: showDialog) {
                        Label("查看对话", systemImage: "text.bubble")
                            .appTypography(.action, fallback: .caption.weight(.semibold))
                            .frame(height: 26)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(appTintColor)
                    .padding(.top, usesRefinedSpacing ? 8 : 2)
                }
            }
        }
        .padding(.vertical, usesRefinedSpacing ? 10 : 9)
        .commentCopyContextMenu(text: reply.content?.message, title: "复制回复")
    }
}
