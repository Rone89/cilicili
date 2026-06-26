import Foundation

extension VideoDetailViewModel {
    func waitForFastStartUpgradeStability(
        startupVariantID: String,
        bvid: String,
        cid: Int,
        startupVariant: PlayVariant,
        targetVariant: PlayVariant,
        generation: Int
    ) async -> Bool {
        try? await Task.sleep(nanoseconds: Self.fastStartUpgradeStabilityDelayNanoseconds)
        guard !Task.isCancelled,
              !isPlaybackInvalidatedForNavigation,
              fastStartUpgradeGeneration == generation,
              isFastStartUpgradeContextCurrent(startupVariantID: startupVariantID, bvid: bvid, cid: cid)
        else {
            clearFastStartUpgradeTaskIfCurrent(generation: generation)
            return false
        }
        guard canPerformStagedStartupUpgrade(from: startupVariantID, bvid: bvid, cid: cid) else {
            recordStagedStartupUpgradeSkipped(
                reason: "unstable",
                startupVariant: startupVariant,
                targetVariant: targetVariant
            )
            clearFastStartUpgradeTaskIfCurrent(generation: generation)
            return false
        }
        return true
    }
}
