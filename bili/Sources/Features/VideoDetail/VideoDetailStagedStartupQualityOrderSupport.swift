import Foundation

extension VideoDetailViewModel {
    func stagedStartupQualityOrder(
        for target: PlayVariant,
        startupCeiling: Int,
        allowsFrameRateFallback: Bool = false
    ) -> [Int] {
        func bounded(_ qualities: [Int]) -> [Int] {
            qualities.filter { $0 <= startupCeiling }
        }
        if variantFrameRate(target) >= 50 {
            if allowsFrameRateFallback {
                switch target.quality {
                case 116...:
                    return bounded([80, 64, 32])
                case 74..<116:
                    return bounded([64, 32])
                default:
                    return []
                }
            }
            return target.quality > 74 ? bounded([74]) : []
        }

        switch target.quality {
        case 120...:
            return bounded([112, 80, 64, 32])
        case 112..<120:
            return bounded([80, 64, 32])
        case 80..<112:
            return bounded([64, 32])
        default:
            return []
        }
    }
}
