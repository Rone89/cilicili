import Foundation

extension VideoDetailViewModel {
    func stopPlaybackForNavigation() {
        guard !isPlaybackInvalidatedForNavigation else { return }
        isPlaybackTerminatedForNavigation = true
        isPlaybackInvalidatedForNavigation = true
        schedulePlaybackStopForNavigation()
    }

    private func schedulePlaybackStopForNavigation() {
        guard navigationState.playbackStopTask == nil else { return }
        navigationState.playbackStopTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            self.navigationState.playbackStopTask = nil
            self.finishStoppingPlaybackForNavigation()
        }
    }

    private func finishStoppingPlaybackForNavigation() {
        cancelPlaybackWorkForNavigation()
        resetPlaybackLoadingStateForNavigation()
        stopStablePlaybackForNavigation()
        resetPlaybackRecoveryStateForNavigation()
    }

    private func cancelPlaybackWorkForNavigation() {
        cancelSupplementalWork()
        Self.cancelMediaWarmupsPreservingCache()
        cancelRelatedLoad()
        cancelCommentsLoadingTask()
        clearCommentThreadLoads()
        resetDanmakuLoad(clearItems: true)
        detailLoadingTask?.cancel()
        detailLoadingTask = nil
        detailLoadingToken = nil
        cancelSponsorBlockTask()
        sponsorBlockSegments = []
        sponsorBlockIdentity = nil
        renderStoreSyncTask?.cancel()
        renderStoreSyncTask = nil
        pendingRenderStoreSyncs = []
        renderStoreSyncGeneration += 1
    }

    private func resetPlaybackLoadingStateForNavigation() {
        selectedPlayVariant = nil
        if state.isLoading {
            state = .idle
        }
        finishPlaybackStartupWaiters(with: nil)
        playURLState = .idle
        shouldResumePlaybackAfterCancelledNavigation = false
        pendingNavigationResumeTime = nil
        hasPendingNavigationInterruption = false
    }

    private func stopStablePlaybackForNavigation() {
        stablePlayerViewModel?.stop()
        stablePlayerViewModel = nil
        clearPlaybackTransitionPlayer()
        stablePlayerIdentity = nil
        stablePlayerErrorCancellable = nil
        stablePlayerFirstFrameCancellable = nil
        syncPlayerIdentityRenderStore()
    }

    private func resetPlaybackRecoveryStateForNavigation() {
        playbackFallbackMessage = nil
        clearManualPlayVariantSelection()
        failedPlayVariantIDs.removeAll()
        playbackRecoveryAttemptCount = 0
        playbackRecoveryCoordinator.reset()
        lastBufferingCDNRefreshCount = 0
        cancelPlaybackRecoveryReloadTask()
        cancelBufferingCDNRefreshTask()
        lastUserSeekAt = nil
        resumeDiagnostics = .none
    }
}
