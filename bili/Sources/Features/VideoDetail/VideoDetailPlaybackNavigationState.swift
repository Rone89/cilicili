import Foundation

struct VideoDetailPlaybackNavigationState {
    var isPlaybackInvalidatedForNavigation = false
    var isPlaybackTerminatedForNavigation = false
    var isPlaybackStopPending = false
    var shouldResumePlaybackAfterCancelledNavigation = false
    var pendingNavigationResumeTime: TimeInterval?
    var hasPendingNavigationInterruption = false
    var isExitingVideoDetailRoute = false
    var didTransferToSystemMiniPlayer = false
}

extension VideoDetailViewModel {
    var isExitingVideoDetailRoute: Bool {
        get { navigationState.isExitingVideoDetailRoute }
        set { navigationState.isExitingVideoDetailRoute = newValue }
    }

    var didTransferToSystemMiniPlayer: Bool {
        get { navigationState.didTransferToSystemMiniPlayer }
        set { navigationState.didTransferToSystemMiniPlayer = newValue }
    }
    var isPlaybackInvalidatedForNavigation: Bool {
        get { navigationState.isPlaybackInvalidatedForNavigation }
        set { navigationState.isPlaybackInvalidatedForNavigation = newValue }
    }

    var isPlaybackTerminatedForNavigation: Bool {
        get { navigationState.isPlaybackTerminatedForNavigation }
        set { navigationState.isPlaybackTerminatedForNavigation = newValue }
    }

    var canActivatePlaybackAfterNavigation: Bool {
        !isPlaybackTerminatedForNavigation && !isPlaybackInvalidatedForNavigation
    }

    var shouldResumePlaybackAfterCancelledNavigation: Bool {
        get { navigationState.shouldResumePlaybackAfterCancelledNavigation }
        set { navigationState.shouldResumePlaybackAfterCancelledNavigation = newValue }
    }

    var pendingNavigationResumeTime: TimeInterval? {
        get { navigationState.pendingNavigationResumeTime }
        set { navigationState.pendingNavigationResumeTime = newValue }
    }

    var hasPendingNavigationInterruption: Bool {
        get { navigationState.hasPendingNavigationInterruption }
        set { navigationState.hasPendingNavigationInterruption = newValue }
    }
}
