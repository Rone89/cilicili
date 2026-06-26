import Foundation

@MainActor
struct VideoDetailPlaybackLoadHostActions {
    let viewModel: VideoDetailViewModel

    var canDeliverPlayerIdentityChange: Bool {
        viewModel.canActivatePlaybackAfterNavigation
    }

    func load() async {
        guard viewModel.canActivatePlaybackAfterNavigation else { return }
        await viewModel.load()
    }
}
