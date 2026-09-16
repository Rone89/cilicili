import SwiftUI

struct CommentRepliesLoadedList: View {
    @Environment(\.videoDetailStandardHorizontalInset) private var standardHorizontalInset
    let snapshot: VideoDetailCommentThreadRepliesSnapshot
    let rootComment: Comment
    let loadMoreReplies: (Comment) async -> Void
    let showDialog: (Comment) -> Void
    let horizontalPadding: CGFloat?

    init(
        snapshot: VideoDetailCommentThreadRepliesSnapshot,
        rootComment: Comment,
        loadMoreReplies: @escaping (Comment) async -> Void,
        showDialog: @escaping (Comment) -> Void,
        horizontalPadding: CGFloat? = nil
    ) {
        self.snapshot = snapshot
        self.rootComment = rootComment
        self.loadMoreReplies = loadMoreReplies
        self.showDialog = showDialog
        self.horizontalPadding = horizontalPadding
    }

    var body: some View {
        let effectiveHorizontalPadding = horizontalPadding ?? standardHorizontalInset

        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(snapshot.replyDisplays) { replyDisplay in
                CommentReplyDetailRow(
                    item: replyDisplay,
                    showDialog: replyDisplay.canShowDialog ? {
                        showDialog(replyDisplay.reply)
                    } : nil
                )
                .padding(.horizontal, effectiveHorizontalPadding)

                Divider()
            }

            CommentRepliesFooter(
                snapshot: snapshot,
                rootComment: rootComment,
                loadMoreReplies: loadMoreReplies
            )
            .padding(.horizontal, effectiveHorizontalPadding)
            .padding(.vertical, 12)
        }
    }
}
