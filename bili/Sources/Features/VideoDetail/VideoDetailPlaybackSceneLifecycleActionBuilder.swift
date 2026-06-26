import Foundation

@MainActor
struct VideoDetailPlaybackSceneLifecycleActionBuilder {
    let lifecycleCoordinator: VideoDetailPlaybackSceneLifecycleCoordinator
    let fullscreenActions: VideoDetailPlaybackSceneFullscreenActions

    var actions: VideoDetailLifecycleActions {
        let rotationActions = VideoDetailPlaybackSceneRotationLifecycleActions(
            fullscreenActions: fullscreenActions
        )
        return VideoDetailLifecycleActions(
            onRotationLayoutTransitionBegan: rotationActions.handleRotationLayoutTransitionBegan,
            onRotationLayoutTransition: rotationActions.handleRotationLayoutTransition,
            onRotationLayoutTransitionCompleted: rotationActions.handleRotationLayoutTransitionCompleted,
            onDeviceOrientationChanged: fullscreenActions.orientation.handleCurrentDeviceOrientation,
            onStopActiveVideoPlayback: lifecycleCoordinator.playback.stopPlaybackForNavigation,
            onPauseActiveVideoPlaybackForNavigation: lifecycleCoordinator.playback.pausePlaybackForPotentialNavigation,
            onResumeActiveVideoPlaybackAfterCancelledNavigation: lifecycleCoordinator.playback.resumePlaybackAfterCancelledNavigation
        )
    }
}
