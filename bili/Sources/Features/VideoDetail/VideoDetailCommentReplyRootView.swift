import SwiftUI

struct CommentReplyRootView: View {
    let comment: Comment
    private let display: CommentRowDisplayModel

    init(comment: Comment) {
        self.comment = comment
        self.display = CommentRowDisplayModel(comment: comment)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CommentAvatar(
                urlString: display.avatarURLString,
                owner: display.authorOwner,
                size: 40
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    CommentAuthorIdentity(name: display.authorName, owner: display.authorOwner)
                        .foregroundStyle(.secondary)

                    if !display.timeText.isEmpty {
                        Text(display.timeText)
                            .appTypography(.metadata, fallback: .caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    CommentLikeButton(comment: comment)
                }

                BiliEmoteText(
                    content: comment.content,
                    font: .subheadline,
                    textColor: .primary,
                    emoteSize: 22,
                    typographyRole: .commentBody
                )
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)

                CommentImageButton(
                    images: display.pictures,
                    transitionScope: comment.id.description
                )
            }
        }
    }
}
