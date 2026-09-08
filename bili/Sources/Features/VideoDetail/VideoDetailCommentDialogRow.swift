import SwiftUI

struct CommentDialogRow: View {
    @Environment(\.appThemeTintColor) private var appTintColor
    @Environment(\.usesDynamicDetailCommentSpacing) private var usesRefinedSpacing

    let item: VideoDetailCommentDialogDisplayItem
    let isFocused: Bool

    private var reply: Comment { item.reply }
    private var display: VideoDetailCommentDisplayModel { item.display }

    init(item: VideoDetailCommentDialogDisplayItem, isFocused: Bool) {
        self.item = item
        self.isFocused = isFocused
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CommentAvatar(
                urlString: display.avatarURLString,
                owner: display.authorOwner,
                size: 36
            )

            VStack(alignment: .leading, spacing: usesRefinedSpacing ? 0 : 11) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    CommentAuthorIdentity(name: display.authorName, owner: display.authorOwner)
                        .foregroundStyle(.secondary)

                    if !display.timeText.isEmpty {
                        Text(display.timeText)
                            .appTypography(.metadata, fallback: .caption)
                            .foregroundStyle(.secondary)
                    }

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
                    .lineSpacing(2)
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
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, isFocused ? 10 : 0)
        .background(isFocused ? appTintColor.opacity(0.06) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .commentCopyContextMenu(text: reply.content?.message, title: "复制回复")
    }
}
