import SwiftUI

struct CommentRowHeader: View {
    let comment: Comment
    let display: VideoDetailCommentDisplayModel

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                CommentAuthorIdentity(name: display.authorName, owner: display.authorOwner)
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                if !display.metadataText.isEmpty {
                    Text(display.metadataText)
                        .appTypography(.metadata, fallback: .caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 38, alignment: .top)

            Spacer(minLength: 8)

            CommentLikeButton(comment: comment)
        }
    }
}
