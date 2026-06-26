import SwiftUI

struct CommentRepliesSheet: View {
    let rootComment: Comment
    let store: VideoDetailCommentThreadRenderStore
    let loadReplies: (Comment) async -> Void
    let reloadReplies: (Comment) async -> Void
    let loadMoreReplies: (Comment) async -> Void
    let loadDialog: (Comment, Comment) async -> Void
    let reloadDialog: (Comment, Comment) async -> Void
    @State private var dialogReply: Comment?

    init(
        rootComment: Comment,
        store: VideoDetailCommentThreadRenderStore,
        loadReplies: @escaping (Comment) async -> Void,
        reloadReplies: @escaping (Comment) async -> Void,
        loadMoreReplies: @escaping (Comment) async -> Void,
        loadDialog: @escaping (Comment, Comment) async -> Void,
        reloadDialog: @escaping (Comment, Comment) async -> Void
    ) {
        self.rootComment = rootComment
        self.store = store
        self.loadReplies = loadReplies
        self.reloadReplies = reloadReplies
        self.loadMoreReplies = loadMoreReplies
        self.loadDialog = loadDialog
        self.reloadDialog = reloadDialog
    }

    var body: some View {
        NavigationStack {
            CommentRepliesSheetContentHost(
                rootComment: rootComment,
                store: store,
                reloadReplies: reloadReplies,
                loadMoreReplies: loadMoreReplies,
                showDialog: showDialog,
                loadReplies: loadReplies
            )
        }
        .presentationDetents([.fraction(0.7)])
        .presentationDragIndicator(.visible)
        .sheet(item: $dialogReply) { reply in
            CommentDialogSheet(
                rootComment: rootComment,
                focusReply: reply,
                store: store,
                loadDialog: loadDialog,
                reloadDialog: reloadDialog
            )
        }
    }

    private func showDialog(_ reply: Comment) {
        dialogReply = reply
    }
}
