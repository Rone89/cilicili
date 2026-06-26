import SwiftUI

struct CommentDialogSheet: View {
    let rootComment: Comment
    let focusReply: Comment
    let store: VideoDetailCommentThreadRenderStore
    let reloadDialog: (Comment, Comment) async -> Void
    let actions: CommentDialogSheetActions

    init(
        rootComment: Comment,
        focusReply: Comment,
        store: VideoDetailCommentThreadRenderStore,
        loadDialog: @escaping (Comment, Comment) async -> Void,
        reloadDialog: @escaping (Comment, Comment) async -> Void
    ) {
        self.rootComment = rootComment
        self.focusReply = focusReply
        self.store = store
        self.reloadDialog = reloadDialog
        actions = CommentDialogSheetActionsBuilder(
            rootComment: rootComment,
            focusReply: focusReply,
            loadDialog: loadDialog
        )
        .actions
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    CommentReplyRootView(comment: rootComment)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                    Divider()

                    CommentDialogContent(
                        rootComment: rootComment,
                        focusReply: focusReply,
                        store: store,
                        reloadDialog: reloadDialog
                    )
                }
            }
            .hiddenInlineNavigationTitle()
            .nativeTopScrollEdgeEffect()
            .commentSheetLoadLifecycle(load: actions.load)
        }
        .presentationDetents([.fraction(0.7)])
        .presentationDragIndicator(.visible)
    }
}
