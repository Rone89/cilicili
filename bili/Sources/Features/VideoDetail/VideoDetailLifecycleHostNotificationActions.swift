import Foundation

struct VideoDetailLifecycleHostNotificationActions {
    let actions: VideoDetailLifecycleActions

    func handleDeviceOrientationChanged() {
        actions.onDeviceOrientationChanged()
    }

    func handleStopActiveVideoPlayback() {
        actions.onStopActiveVideoPlayback()
    }

    func handlePauseActiveVideoPlaybackForNavigation() {
        actions.onPauseActiveVideoPlaybackForNavigation()
    }

    func handleResumeActiveVideoPlaybackAfterCancelledNavigation() {
        actions.onResumeActiveVideoPlaybackAfterCancelledNavigation()
    }
}
