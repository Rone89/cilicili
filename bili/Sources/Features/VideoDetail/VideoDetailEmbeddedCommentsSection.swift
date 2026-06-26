import SwiftUI

struct VideoDetailEmbeddedCommentsSection: View {
    @ObservedObject var viewModel: VideoDetailViewModel
    let renderPack: VideoDetailEmbeddedCommentsSectionRenderPack

    init(
        viewModel: VideoDetailViewModel,
        onReply: @escaping (Comment) -> Void
    ) {
        self.viewModel = viewModel
        renderPack = VideoDetailEmbeddedCommentsSectionRenderPack(
            viewModel: viewModel,
            onReply: onReply
        )
    }

    var body: some View {
        CommentsSectionView(
            store: renderPack.store,
            style: .plain,
            maxVisibleComments: nil,
            autoLoads: true,
            actions: renderPack.actions
        )
    }
}
