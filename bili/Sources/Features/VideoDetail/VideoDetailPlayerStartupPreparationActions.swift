import Foundation

extension VideoDetailViewModel {
    func stablePlayerStartupPreparation(
        resumeTimeOverride: TimeInterval?,
        shouldResumePlayback: Bool?,
        playbackRateOverride: BiliPlaybackRate?
    ) -> StablePlayerStartupPreparation {
        let previousPlayer = stablePlayerViewModel
        let localResumeTime = currentPlaybackResumeTime()
        let resumeCandidate = playbackResumeCandidate(
            resumeTimeOverride: resumeTimeOverride,
            localResumeTime: localResumeTime
        )
        return StablePlayerStartupPreparation(
            previousPlayer: previousPlayer,
            resumeCandidate: resumeCandidate,
            resumeTime: resumeCandidate.time,
            shouldAutoplay: shouldResumePlayback ?? currentPlaybackIntent(),
            playbackRate: playbackRateOverride ?? previousPlayer?.playbackRate ?? .x10
        )
    }

    func preparePreviousStablePlayerForReplacement(
        _ previousPlayer: PlayerStateViewModel?,
        preservesPreviousPlayerUntilFirstFrame: Bool
    ) {
        if preservesPreviousPlayerUntilFirstFrame {
            beginPlaybackTransition(from: previousPlayer)
        } else {
            previousPlayer?.stop(reason: .replacedByAnotherPlayer)
            clearPlaybackTransitionPlayer()
        }
    }
}
