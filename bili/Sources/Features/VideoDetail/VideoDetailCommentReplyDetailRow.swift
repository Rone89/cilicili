import SwiftUI

struct CommentReplyDetailRow: View {
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
            CommentAvatar(urlString: display.avatarURLString, size: 36)

            VStack(alignment: .leading, spacing: 8) {
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
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)

                CommentImageButton(
                    images: display.pictures,
                    transitionScope: reply.id.description
                )

                if let showDialog {
                    Button(action: showDialog) {
                        Label("查看对话", systemImage: "text.bubble")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 9)
                            .frame(height: 26)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.pink)
                    .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 9)
    }
}
