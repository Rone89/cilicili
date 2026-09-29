import SwiftUI

struct CommentRowReplyPreviewSection: View {
    let display: VideoDetailCommentDisplayModel
    let isEnabled: Bool
    let showReplies: () -> Void
    let replyToComment: ((Comment) -> Void)?

    var body: some View {
        if display.visibleReplyCount > 0 {
            CommentReplyPreviewContainer(
                replyCount: display.visibleReplyCount,
                showsPreview: !display.replyPreviews.isEmpty,
                showReplies: showReplies
            ) {
                ForEach(display.replyPreviews) { reply in
                    ReplyPreviewRow(
                        reply: reply,
                        replyToComment: replyToComment,
                        showReplies: showReplies
                    )
                }
            }
            .disabled(!isEnabled)
        }
    }
}
