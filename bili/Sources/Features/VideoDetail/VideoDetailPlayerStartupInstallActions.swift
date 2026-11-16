import Foundation

extension VideoDetailViewModel {
    func installStablePlayerViewModel(
        _ playerViewModel: PlayerStateViewModel,
        variant: PlayVariant,
        resumeCandidate: PlaybackResumeCandidate,
        resumeTime: TimeInterval,
        playbackRate: BiliPlaybackRate,
        shouldAutoplay: Bool,
        playbackHandoffSource: PlayerStateViewModel?
    ) {
        guard !isPlaybackInvalidatedForNavigation else {
            playerViewModel.stop(reason: .navigation)
            return
        }
        configureStablePlayerStartupCallbacks(playerViewModel)
        playerViewModel.setPlaybackRate(playbackRate)
        playerViewModel.setPlaybackIntent(shouldAutoplay)
        playerViewModel.setInitialManualPlaybackPrompt(
            isAwaitingInitialManualPlayback && !shouldAutoplay
        )
        playerViewModel.setRelatedVideoReturnPlaybackPrompt(
            isAwaitingRelatedVideoReturnPlayback && !shouldAutoplay
        )
        stablePlayerViewModel = playerViewModel
        pendingVideoListenPlaybackIntent = nil
        persistVideoListenPlaybackSession(wantsPlayback: shouldAutoplay)
        syncPlayerIdentityRenderStore()
        updateResumeDiagnostics(
            source: resumeCandidate.sourceTitle,
            targetTime: resumeTime > 0.25 ? resumeTime : nil,
            cid: resumeCandidate.cid,
            status: resumeTime > 0.25 ? "创建播放器，等待首轮 seek" : "从头播放",
            reason: resumeCandidate.reason
        )
        logStablePlayerCreated(variant: variant)
        observePlaybackErrors(playerViewModel, variant: variant)
        observeFirstFrameMetrics(playerViewModel, variant: variant, resumeCandidate: resumeCandidate)
        applySponsorBlockSegmentsToPlayer()
        scheduleSponsorBlockSegmentsAfterFirstFrame()
        if shouldAutoplay {
            if let playbackHandoffSource {
                playerViewModel.startSeamlessPlaybackHandoff(from: playbackHandoffSource)
            } else {
                playerViewModel.play()
            }
        }
    }

    func adoptRetainedMiniPlayerSession(_ session: SystemMiniPlayerCoordinator.RetainedSession) {
        let playerViewModel = session.playerViewModel
        detail = session.video
        selectedCID = session.selectedCID
        playVariants = session.playVariants
        selectedPlayVariant = session.selectedPlayVariant
        currentPlayURLData = session.currentPlayURLData
        isDanmakuEnabled = session.isDanmakuEnabled
        hasResolvedDetailMetadata = session.hasResolvedDetailMetadata
        stablePlayerIdentity = session.stablePlayerIdentity
        isAwaitingInitialManualPlayback = false
        isAwaitingRelatedVideoReturnPlayback = false
        state = .loaded
        playURLState = .loaded

        configureStablePlayerStartupCallbacks(playerViewModel)
        playerViewModel.setAutomaticPictureInPictureFromInlineAllowed(
            libraryStore.pictureInPictureEnabled
        )
        playerViewModel.setPictureInPictureEnabled(
            libraryStore.allowsPictureInPictureController
        )
        playerViewModel.beginSurfaceMigrationHold()
        stablePlayerViewModel = playerViewModel
        syncCommentsRenderStore()
        syncPlayerIdentityRenderStore()

        if let variant = session.selectedPlayVariant {
            observePlaybackErrors(playerViewModel, variant: variant)
        }
        applySponsorBlockSegmentsToPlayer()
        scheduleSponsorBlockSegmentsAfterFirstFrame()
        if !session.isRestoringUserInterface {
            Task { @MainActor [weak playerViewModel] in
                await Task.yield()
                playerViewModel?.stopPictureInPictureIfNeeded()
            }
        }
    }
}
