import SwiftUI

struct PortraitCommentsReplySheet: View {
    let comment: Comment
    let store: VideoDetailCommentThreadRenderStore
    let actions: PortraitCommentsSheetReplyActions

    var body: some View {
        CommentRepliesSheet(
            rootComment: comment,
            store: store,
            loadReplies: actions.loadReplies,
            reloadReplies: actions.reloadReplies,
            loadMoreReplies: actions.loadMoreReplies,
            loadDialog: actions.loadDialog,
            reloadDialog: actions.reloadDialog
        )
    }
}
