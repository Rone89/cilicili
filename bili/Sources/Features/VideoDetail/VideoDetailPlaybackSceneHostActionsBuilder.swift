import Foundation

@MainActor
struct VideoDetailPlaybackSceneHostActionsBuilder {
    let viewModel: VideoDetailViewModel

    var actions: VideoDetailPlaybackSceneHostActions {
        VideoDetailPlaybackSceneHostActions(playbackLoad: playbackLoadActions)
    }

    private var playbackLoadActions: VideoDetailPlaybackScenePlaybackLoadActions {
        VideoDetailPlaybackScenePlaybackLoadActions(viewModel: viewModel)
    }
}
