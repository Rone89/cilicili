import Foundation

@MainActor
struct VideoDetailPlaybackSceneFullscreenActionContext {
    let viewModel: VideoDetailViewModel
    let fullscreenCoordinator: VideoDetailFullscreenCoordinator
    let usesSystemNativePlayerUI: Bool

    var canHandlePlaybackPresentation: Bool {
        viewModel.canActivatePlaybackAfterNavigation
    }

    func isCurrentPlayer(_ playerViewModel: PlayerStateViewModel) -> Bool {
        canHandlePlaybackPresentation
            && viewModel.playerIdentityRenderStore.playerViewModel === playerViewModel
            && !playerViewModel.isTerminated
    }

    var playback: VideoDetailPlaybackContext {
        VideoDetailPlaybackContext(
            viewModel: viewModel,
            usesSystemNativePlayerUI: usesSystemNativePlayerUI
        )
    }
}
