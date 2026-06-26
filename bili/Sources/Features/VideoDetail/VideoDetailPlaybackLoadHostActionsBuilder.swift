import Foundation

@MainActor
struct VideoDetailPlaybackLoadHostActionsBuilder {
    let viewModel: VideoDetailViewModel

    var actions: VideoDetailPlaybackLoadHostActions {
        VideoDetailPlaybackLoadHostActions(
            viewModel: viewModel
        )
    }
}
