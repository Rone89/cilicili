import Foundation

extension VideoDetailViewModel {
    func cancelFastStartUpgradeTask(advancesGeneration: Bool = true) {
        fastStartUpgradeTask?.cancel()
        fastStartUpgradeTask = nil
        if advancesGeneration {
            advanceFastStartUpgradeGeneration()
        }
    }

    func cancelHLSRenditionPrebuildTask(advancesGeneration: Bool = true) {
        hlsRenditionPrebuildTask?.cancel()
        hlsRenditionPrebuildTask = nil
        if advancesGeneration {
            advanceHLSRenditionPrebuildGeneration()
        }
    }

    @discardableResult
    func advanceFastStartUpgradeGeneration() -> Int {
        fastStartUpgradeGeneration += 1
        return fastStartUpgradeGeneration
    }

    @discardableResult
    func advanceHLSRenditionPrebuildGeneration() -> Int {
        hlsRenditionPrebuildGeneration += 1
        return hlsRenditionPrebuildGeneration
    }

    func clearFastStartUpgradeTaskIfCurrent(generation: Int) {
        guard fastStartUpgradeGeneration == generation else { return }
        fastStartUpgradeTask = nil
    }

    func clearHLSRenditionPrebuildTaskIfCurrent(generation: Int) {
        guard hlsRenditionPrebuildGeneration == generation else { return }
        hlsRenditionPrebuildTask = nil
    }
}
