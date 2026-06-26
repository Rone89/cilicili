import Foundation

extension VideoDetailViewModel {
    func applyFastStartInPlaceUpgrade(
        playerViewModel: PlayerStateViewModel,
        startupVariant: PlayVariant,
        targetVariant: PlayVariant,
        startupVariantID: String,
        bvid: String,
        cid: Int,
        generation: Int
    ) {
        guard fastStartUpgradeGeneration == generation,
              canPerformStagedStartupUpgrade(from: startupVariantID, bvid: bvid, cid: cid)
        else {
            clearFastStartUpgradeTaskIfCurrent(generation: generation)
            return
        }
        selectedPlayVariant = targetVariant
        stablePlayerIdentity = playerIdentity(for: targetVariant)
        observePlaybackErrors(playerViewModel, variant: targetVariant)
        playbackFallbackMessage = nil
        logSelectedPlayVariant(
            targetVariant,
            availableVariants: playVariants,
            source: "fastStartInPlaceUpgrade"
        )
        PlayerMetricsLog.record(
            .qualitySupplement,
            metricsID: detail.bvid,
            title: detail.title,
            message: "stagedStartup inPlace q\(startupVariant.quality)->q\(targetVariant.quality)"
        )
        clearFastStartUpgradeTaskIfCurrent(generation: generation)
    }

    func applyFastStartPlayerUpgrade(
        startupVariant: PlayVariant,
        optimizedTarget: PlayVariant,
        startupVariantID: String,
        bvid: String,
        cid: Int,
        generation: Int
    ) {
        guard fastStartUpgradeGeneration == generation,
              canPerformStagedStartupUpgrade(from: startupVariantID, bvid: bvid, cid: cid)
        else {
            clearFastStartUpgradeTaskIfCurrent(generation: generation)
            return
        }
        let resumeTime = currentPlaybackResumeTime()
        let shouldResumePlayback = currentPlaybackIntent()
        let playbackRate = stablePlayerViewModel?.playbackRate ?? .x10
        selectedPlayVariant = optimizedTarget
        playbackFallbackMessage = nil
        logSelectedPlayVariant(
            optimizedTarget,
            availableVariants: playVariants,
            source: "fastStartUpgrade"
        )
        PlayerMetricsLog.record(
            .qualitySupplement,
            metricsID: detail.bvid,
            title: detail.title,
            message: "stagedStartup upgrade q\(startupVariant.quality)->q\(optimizedTarget.quality) at=\(String(format: "%.2fs", resumeTime))"
        )
        updateStablePlayerViewModelIfNeeded(
            resumeTimeOverride: resumeTime,
            shouldResumePlayback: shouldResumePlayback,
            playbackRateOverride: playbackRate,
            preservesPreviousPlayerUntilFirstFrame: true
        )
        clearFastStartUpgradeTaskIfCurrent(generation: generation)
    }
}
