import Foundation

extension VideoDetailViewModel {
    func installStablePlayerViewModel(
        _ playerViewModel: PlayerStateViewModel,
        variant: PlayVariant,
        resumeCandidate: PlaybackResumeCandidate,
        resumeTime: TimeInterval,
        playbackRate: BiliPlaybackRate,
        shouldAutoplay: Bool
    ) {
        guard !isPlaybackInvalidatedForNavigation else {
            playerViewModel.stop(reason: .navigation)
            return
        }
        configureStablePlayerStartupCallbacks(playerViewModel)
        playerViewModel.setPlaybackRate(playbackRate)
        playerViewModel.setPlaybackIntent(shouldAutoplay)
        stablePlayerViewModel = playerViewModel
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
            playerViewModel.play()
        }
    }
}
