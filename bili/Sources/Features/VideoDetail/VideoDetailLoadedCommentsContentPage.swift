import SwiftUI

struct VideoDetailLoadedCommentsContentPage: View {
    let viewModel: VideoDetailViewModel
    let onReply: (Comment) -> Void

    var body: some View {
        VideoDetailEmbeddedCommentsSection(
            viewModel: viewModel,
            onReply: onReply
        )
        .padding(.top, VideoDetailContentPageMetrics.commentsTopPadding)
    }
}
