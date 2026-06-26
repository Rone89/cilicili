import SwiftUI

struct CommentRow: View, Equatable {
    let item: VideoDetailCommentDisplayItem
    let style: CommentSectionStyle
    let showReplies: () -> Void

    private var comment: Comment { item.comment }
    private var display: VideoDetailCommentDisplayModel { item.display }

    init(
        item: VideoDetailCommentDisplayItem,
        style: CommentSectionStyle,
        showReplies: @escaping () -> Void
    ) {
        self.item = item
        self.style = style
        self.showReplies = showReplies
    }

    static func == (lhs: CommentRow, rhs: CommentRow) -> Bool {
        lhs.item == rhs.item && lhs.style == rhs.style
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CommentAvatar(urlString: display.avatarURLString, size: 38)

            VStack(alignment: .leading, spacing: 5) {
                CommentRowHeader(display: display)

                BiliEmoteText(content: comment.content, font: .subheadline, textColor: .primary, emoteSize: 21)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)

                CommentImageButton(
                    images: display.pictures,
                    transitionScope: comment.id.description
                )

                CommentRowReplyPreviewSection(
                    display: display,
                    isEnabled: style.showsReplyPreviewContainer,
                    showReplies: showReplies
                )
            }
        }
        .padding(.vertical, 8)
    }
}
