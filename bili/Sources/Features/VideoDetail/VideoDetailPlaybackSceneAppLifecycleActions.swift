import Foundation

@MainActor
struct VideoDetailPlaybackSceneAppLifecycleActions {
    let viewModel: VideoDetailViewModel
    let fullscreenActions: VideoDetailPlaybackSceneFullscreenActions
    let isClosingDetail: () -> Bool

    func handleSceneBecameActive() {
        guard !isClosingDetail(),
              viewModel.canActivatePlaybackAfterNavigation
        else { return }
        fullscreenActions.recovery.restorePortraitWhenInactive()
        fullscreenActions.orientation.handleCurrentDeviceOrientation()
        viewModel.recoverPlaybackAfterAppResume()
    }
}
