import SwiftUI

@MainActor
struct VideoDetailReplySheetHost: View {
    let rootComment: Comment
    @ObservedObject var viewModel: VideoDetailViewModel
    let renderPack: VideoDetailReplySheetRenderPack

    init(
        rootComment: Comment,
        viewModel: VideoDetailViewModel,
        actions: VideoDetailReplySheetActions
    ) {
        self.rootComment = rootComment
        self.viewModel = viewModel
        renderPack = VideoDetailReplySheetRenderPack(
            viewModel: viewModel,
            actions: actions
        )
    }

    var body: some View {
        CommentRepliesSheet(
            rootComment: rootComment,
            store: renderPack.store,
            loadReplies: renderPack.actions.loadReplies,
            reloadReplies: renderPack.actions.reloadReplies,
            loadMoreReplies: renderPack.actions.loadMoreReplies,
            loadDialog: renderPack.actions.loadDialog,
            reloadDialog: renderPack.actions.reloadDialog
        )
    }
}
