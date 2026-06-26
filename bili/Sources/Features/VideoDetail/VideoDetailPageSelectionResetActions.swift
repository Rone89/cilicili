import Foundation

extension VideoDetailViewModel {
    func resetPlaybackStateForSelectedPage() {
        resetDanmakuLoad(clearItems: true)
        playVariants = []
        selectedPlayVariant = nil
        playURLElapsedMilliseconds = nil
        lastPlayURLSource = nil
        didSelectPlayVariantManually = false
        failedPlayVariantIDs.removeAll()
        playbackRecoveryAttemptCount = 0
        playbackRecoveryCoordinator.reset()
        lastBufferingCDNRefreshCount = 0
        cancelPlaybackRecoveryReloadTask()
        cancelBufferingCDNRefreshTask()
        finishPlaybackStartupWaiters(with: nil)
        stablePlayerViewModel?.stop()
        stablePlayerViewModel = nil
        clearPlaybackTransitionPlayer()
        stablePlayerIdentity = nil
        stablePlayerErrorCancellable = nil
        stablePlayerFirstFrameCancellable = nil
        syncPlayerIdentityRenderStore()
        playbackFallbackMessage = nil
        cancelPlayURLSupplementTask()
        cancelPlayVariantSwitchTask()
        cancelCommentsLoadingTask()
        clearCommentThreadLoads()
        cancelStartupPlayURLTask()
        cancelFastStartUpgradeTask()
        cancelHLSRenditionPrebuildTask()
        cancelSeekWarmups(clearRecent: true)
        isSupplementingPlayQualities = false
        cancelSponsorBlockTask()
        sponsorBlockSegments = []
        sponsorBlockIdentity = nil
        playURLState = .idle
    }
}
