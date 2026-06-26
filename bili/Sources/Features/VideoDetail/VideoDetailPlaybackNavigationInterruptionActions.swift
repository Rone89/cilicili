import Foundation

extension VideoDetailViewModel {
    func suspendPlaybackForNavigation() {
        guard canActivatePlaybackAfterNavigation else { return }
        stablePlayerViewModel?.suspendForNavigation()
    }

    func pausePlaybackForPotentialNavigation() {
        guard canActivatePlaybackAfterNavigation, let player = stablePlayerViewModel else { return }
        let resumeTime = currentPlaybackResumeTime()
        if resumeTime > 0.25 {
            pendingNavigationResumeTime = max(pendingNavigationResumeTime ?? 0, resumeTime)
        }
        hasPendingNavigationInterruption = true
        let shouldResume = player.wantsAutoplay
            || player.isPlaying
            || player.playbackSnapshot().isPlaying
        shouldResumePlaybackAfterCancelledNavigation = shouldResumePlaybackAfterCancelledNavigation || shouldResume
        player.suspendForNavigation()
    }
}
