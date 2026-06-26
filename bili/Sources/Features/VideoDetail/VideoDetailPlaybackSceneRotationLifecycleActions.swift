import Foundation

@MainActor
struct VideoDetailPlaybackSceneRotationLifecycleActions {
    let fullscreenActions: VideoDetailPlaybackSceneFullscreenActions

    func handleRotationLayoutTransitionBegan() {
        fullscreenActions.orientation.beginSystemRotationLayoutTransition()
    }

    func handleRotationLayoutTransition() {
        fullscreenActions.orientation.refreshActivePlayerSurfaceLayout(
            coordinatedWithSwiftUILayout: true
        )
    }

    func handleRotationLayoutTransitionCompleted() {
        fullscreenActions.orientation.finishSystemRotationLayoutTransition()
    }
}
