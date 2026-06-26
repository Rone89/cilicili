import Foundation

@MainActor
struct VideoDetailPlaybackSceneHostActionBuilder {
    let lifecycleCoordinator: VideoDetailPlaybackSceneLifecycleCoordinator
    let fullscreenActions: VideoDetailPlaybackSceneFullscreenActions

    var lifecycle: VideoDetailPlaybackSceneLifecycleActions {
        VideoDetailPlaybackSceneLifecycleActions(
            lifecycle: lifecycleActionBuilder.actions,
            navigation: navigationActionBuilder.actions
        )
    }

    private var lifecycleActionBuilder: VideoDetailPlaybackSceneLifecycleActionBuilder {
        VideoDetailPlaybackSceneLifecycleActionBuilder(
            lifecycleCoordinator: lifecycleCoordinator,
            fullscreenActions: fullscreenActions
        )
    }

    private var navigationActionBuilder: VideoDetailPlaybackSceneNavigationActionBuilder {
        VideoDetailPlaybackSceneNavigationActionBuilder(
            lifecycleCoordinator: lifecycleCoordinator
        )
    }
}
