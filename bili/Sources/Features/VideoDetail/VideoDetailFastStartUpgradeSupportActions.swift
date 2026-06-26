import Foundation

struct VideoDetailFastStartUpgradeTarget {
    let canUpgradeInPlace: Bool
    let optimizedTarget: PlayVariant
}

extension VideoDetailViewModel {
    func isFastStartUpgradeContextCurrent(startupVariantID: String, bvid: String, cid: Int) -> Bool {
        !Task.isCancelled
            && !isPlaybackInvalidatedForNavigation
            && detail.bvid == bvid
            && selectedCID == cid
            && selectedPlayVariant?.id == startupVariantID
    }
}
