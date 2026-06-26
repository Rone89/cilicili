import Foundation

extension VideoDetailViewModel {
    func warmAndApplyFastStartUpgrade(
        _ target: VideoDetailFastStartUpgradeTarget,
        startupVariant: PlayVariant,
        targetVariant: PlayVariant,
        startupVariantID: String,
        bvid: String,
        cid: Int,
        page: Int?,
        generation: Int
    ) async {
        let didWarmTarget = await VideoPreloadCenter.shared.warmVariantAndWaitCached(
            target.optimizedTarget,
            bvid: bvid,
            cid: cid,
            page: page,
            delay: 0,
            timeout: Self.fastStartUpgradeWarmupTimeout
        )

        if !didWarmTarget {
            PlayerMetricsLog.record(
                .qualitySupplement,
                metricsID: detail.bvid,
                title: detail.title,
                message: "stagedStartup warmTimeoutContinue q\(startupVariant.quality)->q\(target.optimizedTarget.quality)"
            )
        }
        guard !Task.isCancelled,
              !isPlaybackInvalidatedForNavigation,
              fastStartUpgradeGeneration == generation,
              canPerformStagedStartupUpgrade(from: startupVariantID, bvid: bvid, cid: cid)
        else {
            let reason = didWarmTarget ? "changedDuringWarmup" : "unstableAfterWarmTimeout"
            recordStagedStartupUpgradeSkipped(
                reason: reason,
                startupVariant: startupVariant,
                targetVariant: target.optimizedTarget
            )
            clearFastStartUpgradeTaskIfCurrent(generation: generation)
            return
        }

        if target.canUpgradeInPlace,
           let playerViewModel = stablePlayerViewModel,
           playerViewModel.preferVideoRenditionInCurrentItem(targetVariant) {
            applyFastStartInPlaceUpgrade(
                playerViewModel: playerViewModel,
                startupVariant: startupVariant,
                targetVariant: targetVariant,
                startupVariantID: startupVariantID,
                bvid: bvid,
                cid: cid,
                generation: generation
            )
            return
        }

        applyFastStartPlayerUpgrade(
            startupVariant: startupVariant,
            optimizedTarget: target.optimizedTarget,
            startupVariantID: startupVariantID,
            bvid: bvid,
            cid: cid,
            generation: generation
        )
    }
}
