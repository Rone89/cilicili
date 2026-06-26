import Foundation

extension VideoDetailViewModel {
    func createAndInstallStablePlayer(
        variant: PlayVariant,
        startupPreparation: StablePlayerStartupPreparation
    ) {
        guard !isPlaybackInvalidatedForNavigation else { return }
        let signpostState = PlayerMetricsLog.beginSignpostedInterval(
            "PlayerCreate",
            message: "bvid=\(detail.bvid) cid=\(selectedCID ?? 0) q=\(variant.quality)"
        )
        var signpostMessage = "bvid=\(detail.bvid) creating"
        defer {
            PlayerMetricsLog.endSignpostedInterval(
                "PlayerCreate",
                signpostState,
                message: signpostMessage
            )
        }

        let alternateVideoRenditions = hlsAlternateVideoRenditions(for: variant)
        recordHLSVideoVariantPlan(
            startupVariant: variant,
            alternateVideoRenditions: alternateVideoRenditions
        )
        let playerViewModel = makeStablePlayerViewModel(
            variant: variant,
            alternateVideoRenditions: alternateVideoRenditions,
            resumeTime: startupPreparation.resumeTime
        )
        installStablePlayerViewModel(
            playerViewModel,
            variant: variant,
            resumeCandidate: startupPreparation.resumeCandidate,
            resumeTime: startupPreparation.resumeTime,
            playbackRate: startupPreparation.playbackRate,
            shouldAutoplay: startupPreparation.shouldAutoplay
        )
        signpostMessage = "bvid=\(detail.bvid) ready autoplay=\(startupPreparation.shouldAutoplay)"
    }
}
