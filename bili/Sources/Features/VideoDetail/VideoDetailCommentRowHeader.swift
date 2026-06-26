import SwiftUI

struct CommentRowHeader: View {
    let display: VideoDetailCommentDisplayModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(display.authorName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

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
    }
}
