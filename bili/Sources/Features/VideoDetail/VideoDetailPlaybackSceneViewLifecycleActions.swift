import UIKit

@MainActor
struct VideoDetailPlaybackSceneViewLifecycleActions {
    let runtimeSettings: VideoDetailRuntimeSettingsStore
    let libraryStore: LibraryStore
    let fullscreenActions: VideoDetailPlaybackSceneFullscreenActions
    let playbackActions: VideoDetailPlaybackScenePlaybackLifecycleActions
    let isClosingDetail: () -> Bool

    private var shouldIgnorePlaybackRecovery: Bool {
        isClosingDetail()
    }

    func handleViewAppear() {
        runtimeSettings.bind(libraryStore)
        guard !shouldIgnorePlaybackRecovery else { return }
        fullscreenActions.recovery.restorePortraitWhenInactive()
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        fullscreenActions.orientation.handleCurrentDeviceOrientation()
        playbackActions.resumePlaybackAfterCoveredNavigationIfNeeded()
    }

    func handleViewDisappear() {
        fullscreenActions.recovery.resetForDisappear()
        playbackActions.stopOrPausePlaybackForDisappear()
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }
}
