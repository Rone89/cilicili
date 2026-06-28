import SwiftUI

struct DynamicCommentReplyAuthorLine: View {
    let display: DynamicCommentRowDisplayModel
    let showsLike: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(display.authorName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if !display.timeText.isEmpty {
                Text(display.timeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if showsLike {
                Spacer(minLength: 8)
                DynamicCommentReplyLikeLabel(display: display)
            }
        }
    }
}

private struct DynamicCommentReplyLikeLabel: View {
    @Environment(\.appThemeTintColor) private var appTintColor

    let display: DynamicCommentRowDisplayModel

    var body: some View {
        Label(display.likeText, systemImage: display.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
            .font(.caption)
            .foregroundStyle(display.isLiked ? appTintColor : .secondary)
            .labelStyle(.titleAndIcon)
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
            lineSpacing: 2
        )

        DynamicCommentImageGrid(images: display.pictures)
    }
}
