import Foundation

extension VideoDetailViewModel {
    func scheduleFastStartUpgradeIfNeeded(
        from startupVariant: PlayVariant?,
        to targetVariant: PlayVariant?,
        cid: Int?,
        page: Int?
    ) {
        cancelFastStartUpgradeTask(advancesGeneration: false)
        let upgradeGeneration = advanceFastStartUpgradeGeneration()
        guard !didSelectPlayVariantManually,
              let cid,
              let startupVariant,
              let targetVariant,
              startupVariant.id != targetVariant.id,
              targetVariant.isPlayable,
              shouldScheduleStagedStartupUpgrade(from: startupVariant, to: targetVariant)
        else { return }

        let startupVariantID = startupVariant.id
        let bvid = detail.bvid
        PlayerMetricsLog.record(
            .qualitySupplement,
            metricsID: detail.bvid,
            title: detail.title,
            message: "stagedStartup queued q\(startupVariant.quality)->q\(targetVariant.quality)"
        )
        fastStartUpgradeTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            defer {
                self.clearFastStartUpgradeTaskIfCurrent(generation: upgradeGeneration)
            }
            let didPresentPlayback = await self.waitForFirstFrameOrFailure()
            guard didPresentPlayback,
                  !Task.isCancelled,
                  !self.isPlaybackInvalidatedForNavigation,
                  self.fastStartUpgradeGeneration == upgradeGeneration,
                  self.isFastStartUpgradeContextCurrent(startupVariantID: startupVariantID, bvid: bvid, cid: cid)
            else { return }
            guard await self.waitForFastStartUpgradeStability(
                startupVariantID: startupVariantID,
                bvid: bvid,
                cid: cid,
                startupVariant: startupVariant,
                targetVariant: targetVariant,
                generation: upgradeGeneration
            ) else { return }
            guard let target = await self.resolvedFastStartUpgradeTarget(
                startupVariant: startupVariant,
                targetVariant: targetVariant,
                startupVariantID: startupVariantID,
                bvid: bvid,
                cid: cid,
                generation: upgradeGeneration
            ) else { return }
            await self.warmAndApplyFastStartUpgrade(
                target,
                startupVariant: startupVariant,
                targetVariant: targetVariant,
                startupVariantID: startupVariantID,
                bvid: bvid,
                cid: cid,
                page: page,
                generation: upgradeGeneration
            )
        }
    }
}
