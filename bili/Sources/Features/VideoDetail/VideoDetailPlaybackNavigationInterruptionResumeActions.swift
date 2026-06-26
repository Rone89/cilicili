import Foundation

extension VideoDetailViewModel {
    func resumePlaybackAfterNavigationInterruptionIfNeeded() {
        guard canActivatePlaybackAfterNavigation else { return }
        guard state == .loaded else { return }
        let shouldResume = shouldResumePlaybackAfterCancelledNavigation
        let resumeTime = pendingNavigationResumeTime
        let shouldResumeOverride: Bool? = shouldResume
            ? true
            : (hasPendingNavigationInterruption ? false : nil)
        discardTerminatedStablePlayerIfNeeded()
        defer {
            shouldResumePlaybackAfterCancelledNavigation = false
            pendingNavigationResumeTime = nil
            hasPendingNavigationInterruption = false
        }
        guard let player = stablePlayerViewModel else {
            if selectedPlayVariant?.isPlayable == true {
                updateStablePlayerViewModelIfNeeded(
                    resumeTimeOverride: resumeTime,
                    shouldResumePlayback: shouldResumeOverride
                )
            } else {
                schedulePlayURLLoadIfNeeded()
            }
            return
        }
        player.restoreAudioAfterCancelledNavigation()
        guard shouldResume else { return }
        player.play()
    }
}
