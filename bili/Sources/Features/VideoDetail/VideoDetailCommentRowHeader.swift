import SwiftUI

struct CommentRowHeader: View {
    let comment: Comment
    let display: VideoDetailCommentDisplayModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            CommentAuthorIdentity(name: display.authorName, owner: display.authorOwner)
                .foregroundStyle(.primary)

            if !display.timeText.isEmpty {
                Text(display.timeText)
                    .appTypography(.metadata, fallback: .caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            CommentLikeButton(comment: comment)
        }
    }
}
