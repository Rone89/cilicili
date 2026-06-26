import Foundation

extension VideoDetailViewModel {
    func resolvedFastStartUpgradeTarget(
        startupVariant: PlayVariant,
        targetVariant: PlayVariant,
        startupVariantID: String,
        bvid: String,
        cid: Int,
        generation: Int
    ) async -> VideoDetailFastStartUpgradeTarget? {
        guard !Task.isCancelled,
              !isPlaybackInvalidatedForNavigation,
              fastStartUpgradeGeneration == generation,
              isFastStartUpgradeContextCurrent(startupVariantID: startupVariantID, bvid: bvid, cid: cid)
        else {
            clearFastStartUpgradeTaskIfCurrent(generation: generation)
            return nil
        }
        let canUpgradeInPlace = stablePlayerViewModel?.engineDiagnostics.hlsVideoVariantCount ?? 0 > 1
            && canPerformInPlaceHLSVariantUpgrade(from: startupVariant, to: targetVariant)
        let optimizedTarget = canUpgradeInPlace
            ? targetVariant
            : await optimizedStartupVariant(targetVariant, source: "fastStartUpgrade") ?? targetVariant
        guard !Task.isCancelled,
              !isPlaybackInvalidatedForNavigation,
              fastStartUpgradeGeneration == generation,
              isFastStartUpgradeContextCurrent(startupVariantID: startupVariantID, bvid: bvid, cid: cid)
        else {
            clearFastStartUpgradeTaskIfCurrent(generation: generation)
            return nil
        }

        if optimizedTarget.id != targetVariant.id {
            playVariants = replacingVariant(
                in: playVariants,
                matching: targetVariant.id,
                with: optimizedTarget
            )
        }
        return VideoDetailFastStartUpgradeTarget(
            canUpgradeInPlace: canUpgradeInPlace,
            optimizedTarget: optimizedTarget
        )
    }
}
