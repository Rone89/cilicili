import Foundation

@MainActor
struct VideoDetailPlaybackSceneCloseActionBuilder {
    let callbacks: VideoDetailPlaybackSceneCloseCallbacks
    let viewModel: VideoDetailViewModel
    let fullscreenActions: VideoDetailPlaybackSceneFullscreenActions

    var actions: VideoDetailPlaybackSceneCloseActions {
        VideoDetailPlaybackSceneCloseActions(
            state: stateActions,
            navigation: navigationActions
        )
    }

    private var stateActions: VideoDetailPlaybackSceneCloseStateActions {
        VideoDetailPlaybackSceneCloseStateActions(
            isClosingDetail: callbacks.isClosingDetail,
            markClosingDetail: callbacks.markClosingDetail
        )
    }

    private var navigationActions: VideoDetailPlaybackSceneCloseNavigationActions {
        VideoDetailPlaybackSceneCloseNavigationActions(
            resetFullscreenForClose: fullscreenActions.recovery.resetForDisappear,
            stopPlaybackForNavigation: viewModel.stopPlaybackForNavigation,
            onNavigateBack: callbacks.onNavigateBack
        )
    }
}
