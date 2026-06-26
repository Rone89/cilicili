import SwiftUI

struct CommentDialogRow: View {
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
            CommentAvatar(urlString: display.avatarURLString, size: 36)

            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(display.authorName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if !display.timeText.isEmpty {
                        Text(display.timeText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    CommentMetricBadge(
                        text: display.likeText,
                        systemImage: display.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup",
                        isHighlighted: display.isLiked
                    )
                }

                BiliEmoteText(content: reply.content, font: .subheadline, textColor: .primary, emoteSize: 22)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                CommentImageButton(
                    images: display.pictures,
                    transitionScope: reply.id.description
                )
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, isFocused ? 10 : 0)
        .background(isFocused ? Color.pink.opacity(0.06) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
