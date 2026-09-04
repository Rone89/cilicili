import SwiftUI

struct DynamicCommentReplyAuthorLine: View {
    let comment: Comment
    let display: DynamicCommentRowDisplayModel
    let showsLike: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                CommentAuthorIdentity(name: display.authorName, owner: display.authorOwner)
                    .foregroundStyle(.secondary)

                if !display.timeText.isEmpty {
                    Text(display.timeText)
                        .appTypography(.metadata, fallback: .caption)
                        .foregroundStyle(.secondary)
                }
            }

            if showsLike {
                Spacer(minLength: 8)
                CommentLikeButton(comment: comment)
            }
        }
    }
}

struct DynamicCommentReplyBody: View {
    let comment: Comment
    let display: DynamicCommentRowDisplayModel

    var body: some View {
        DynamicCommentText(
            content: comment.content,
            font: .subheadline,
            textColor: .primary,
            emoteSize: 22,
            lineSpacing: 2,
            typographyRole: .commentBody
        )
        DynamicCommentImageGrid(images: display.pictures)
    }
}
