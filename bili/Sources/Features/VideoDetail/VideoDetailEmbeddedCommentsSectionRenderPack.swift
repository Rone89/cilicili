import Foundation

@MainActor
struct VideoDetailEmbeddedCommentsSectionRenderPack {
    let store: VideoDetailCommentsRenderStore
    let actions: VideoDetailCommentsSectionActions

    init(
        viewModel: VideoDetailViewModel,
        onReply: @escaping (Comment) -> Void
    ) {
        store = viewModel.commentsRenderStore
        actions = VideoDetailEmbeddedCommentsSectionActionsBuilder(
            viewModel: viewModel,
            onReply: onReply
        )
        .actions
    }
}
