import Foundation

@MainActor
struct VideoDetailPlaybackSceneFullscreenActions {
    let orientation: VideoDetailPlaybackSceneFullscreenOrientationActions
    let recovery: VideoDetailPlaybackSceneFullscreenRecoveryActions
    let presentation: VideoDetailPlaybackSceneFullscreenPresentationActions

    init(
        viewModel: VideoDetailViewModel,
        fullscreenCoordinator: VideoDetailFullscreenCoordinator,
        usesSystemNativePlayerUI: Bool
    ) {
        let context = VideoDetailPlaybackSceneFullscreenActionContext(
            viewModel: viewModel,
            fullscreenCoordinator: fullscreenCoordinator,
            usesSystemNativePlayerUI: usesSystemNativePlayerUI
        )
        orientation = VideoDetailPlaybackSceneFullscreenOrientationActions(context: context)
        recovery = VideoDetailPlaybackSceneFullscreenRecoveryActions(context: context)
        presentation = VideoDetailPlaybackSceneFullscreenPresentationActions(context: context)
    }
}
