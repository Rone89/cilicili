import SwiftUI

struct CommentRepliesSheet: View {
    let rootComment: Comment
    @ObservedObject var store: VideoDetailCommentThreadRenderStore
    let initialReplyID: Int?
    let loadReplies: (Comment) async -> Void
    let reloadReplies: (Comment) async -> Void
    let loadMoreReplies: (Comment) async -> Void
    let loadDialog: (Comment, Comment) async -> Void
    let reloadDialog: (Comment, Comment) async -> Void
    @State private var dialogReply: Comment?
    @State private var didPresentInitialReply = false

    init(
        rootComment: Comment,
        store: VideoDetailCommentThreadRenderStore,
        initialReplyID: Int? = nil,
        loadReplies: @escaping (Comment) async -> Void,
        reloadReplies: @escaping (Comment) async -> Void,
        loadMoreReplies: @escaping (Comment) async -> Void,
        loadDialog: @escaping (Comment, Comment) async -> Void,
        reloadDialog: @escaping (Comment, Comment) async -> Void
    ) {
        self.rootComment = rootComment
        self.store = store
        self.initialReplyID = initialReplyID
        self.loadReplies = loadReplies
        self.reloadReplies = reloadReplies
        self.loadMoreReplies = loadMoreReplies
        self.loadDialog = loadDialog
        self.reloadDialog = reloadDialog
    }

    var body: some View {
        CommentOwnerProfileNavigationContainer {
            CommentRepliesSheetContentHost(
                rootComment: rootComment,
                store: store,
                reloadReplies: reloadReplies,
                loadMoreReplies: loadMoreReplies,
                showDialog: showDialog,
                loadReplies: loadReplies
            )
        }
        .commentSheetPresentation()
        .sheet(item: $dialogReply) { reply in
            CommentDialogSheet(
                rootComment: rootComment,
                focusReply: reply,
                store: store,
                loadDialog: loadDialog,
                reloadDialog: reloadDialog
            )
        }
        .onChange(of: replyIDs) { _, _ in
            presentInitialReplyIfAvailable()
        }
        .onAppear {
            presentInitialReplyIfAvailable()
        }
    }

    private func showDialog(_ reply: Comment) {
        dialogReply = reply
    }

    private var replyIDs: [Int] {
        store.replies(for: rootComment).map(\.id)
    }

    private func presentInitialReplyIfAvailable() {
        guard !didPresentInitialReply,
              dialogReply == nil,
              let initialReplyID,
              let reply = store.replies(for: rootComment).first(where: { $0.id == initialReplyID })
        else {
            return
        }
        didPresentInitialReply = true
        dialogReply = reply
    }
}
