import Foundation

extension VideoDetailViewModel {
    func resumePlaybackAfterCancelledNavigation() {
        resumePlaybackAfterNavigationInterruptionIfNeeded()
    }

    func resumePlaybackAfterCoveredNavigationIfNeeded() {
        resumePlaybackAfterNavigationInterruptionIfNeeded()
    }

    func recoverPlaybackAfterAppResume() {
        guard canActivatePlaybackAfterNavigation else { return }
        discardTerminatedStablePlayerIfNeeded()
        guard let player = stablePlayerViewModel else {
            if selectedPlayVariant?.isPlayable == true {
                updateStablePlayerViewModelIfNeeded(
                    resumeTimeOverride: pendingNavigationResumeTime ?? currentPlaybackResumeTime(),
                    shouldResumePlayback: true
                )
                pendingNavigationResumeTime = nil
            } else {
                schedulePlayURLLoadIfNeeded()
            }
            return
        }
        let shouldResume = player.wantsAutoplay || player.isPlaying || player.playbackSnapshot().isPlaying
        player.recoverPlaybackAfterAppResume()
        if shouldResume, let message = player.errorMessage, let selectedPlayVariant {
            handlePlaybackError(message, for: selectedPlayVariant)
        }
    }

    func cancelPlaybackNavigationStop() {
        guard canActivatePlaybackAfterNavigation else { return }
        discardTerminatedStablePlayerIfNeeded()
        guard let player = stablePlayerViewModel else { return }
        player.setPlaybackIntent(true)
        guard stablePlayerViewModel === player,
              canActivatePlaybackAfterNavigation
        else { return }
        player.recoverPlaybackAfterAppResume()
    }
}
