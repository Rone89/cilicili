import Foundation

extension VideoDetailViewModel {
    func updateStablePlayerViewModelIfNeeded(
        resumeTimeOverride: TimeInterval? = nil,
        shouldResumePlayback: Bool? = nil,
        playbackRateOverride: BiliPlaybackRate? = nil,
        preservesPreviousPlayerUntilFirstFrame: Bool = false
    ) {
        guard !isPlaybackInvalidatedForNavigation else { return }
        guard let variant = selectedPlayVariant, variant.isPlayable else {
            resetStablePlayerForMissingVariant()
            return
        }

        let identity = playerIdentity(for: variant)
        if applyStableIdentityResumeIfNeeded(
            identity: identity,
            resumeTimeOverride: resumeTimeOverride,
            shouldResumePlayback: shouldResumePlayback,
            playbackRateOverride: playbackRateOverride
        ) {
            return
        }

        let startupPreparation = stablePlayerStartupPreparation(
            resumeTimeOverride: resumeTimeOverride,
            shouldResumePlayback: shouldResumePlayback,
            playbackRateOverride: playbackRateOverride
        )
        preparePreviousStablePlayerForReplacement(
            startupPreparation.previousPlayer,
            preservesPreviousPlayerUntilFirstFrame: preservesPreviousPlayerUntilFirstFrame
        )
        resetStablePlayerObserversForNewIdentity(identity)
        createAndInstallStablePlayer(
            variant: variant,
            startupPreparation: startupPreparation
        )
    }

}
