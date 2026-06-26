import Foundation

@MainActor
struct VideoDetailPlaybackSceneNavigationActionBuilder {
    let lifecycleCoordinator: VideoDetailPlaybackSceneLifecycleCoordinator

    var actions: VideoDetailNavigationPlaybackActions {
        VideoDetailNavigationPlaybackActions(
            onNavigationWillDisappear: lifecycleCoordinator.playback.pausePlaybackForPotentialNavigation,
            onNavigationDidAppear: lifecycleCoordinator.playback.resumePlaybackAfterCoveredNavigationIfNeeded,
            onNavigationTransitionCompleted: lifecycleCoordinator.playback.handleNavigationTransitionCompleted,
            onSystemBackGestureBegan: lifecycleCoordinator.playback.pausePlaybackForPotentialNavigation,
            onAppear: lifecycleCoordinator.view.handleViewAppear,
            onDisappear: lifecycleCoordinator.view.handleViewDisappear,
            onSceneBecameActive: lifecycleCoordinator.app.handleSceneBecameActive
        )
    }
}
