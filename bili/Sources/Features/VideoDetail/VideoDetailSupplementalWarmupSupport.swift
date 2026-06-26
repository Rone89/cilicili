import Foundation

extension VideoDetailViewModel {
    func supplementalWarmupVariants() -> [PlayVariant] {
        let selectedVariantID = selectedPlayVariant?.id
        var result = [PlayVariant]()

        func append(_ variant: PlayVariant?) {
            guard let variant,
                  variant.id != selectedVariantID,
                  !result.contains(where: { $0.id == variant.id })
            else { return }
            result.append(variant)
        }

        append(likelySupplementalWarmupVariant())
        append(dolbyVisionWarmupVariant())
        return result
    }

    func likelySupplementalWarmupVariant() -> PlayVariant? {
        let playableVariants = playVariants.filter(\.isPlayable)
        var preferredWarmupQualities = [Int]()
        if let preferredQuality = libraryStore.preferredVideoQuality {
            preferredWarmupQualities.append(preferredQuality)
        }
        preferredWarmupQualities += [116, 112, 120, 80, 74]
        for quality in preferredWarmupQualities {
            if let variant = playableVariants.first(where: { $0.quality == quality && !$0.isProgressiveFastStart }) {
                return variant
            }
        }
        return playableVariants
            .filter { !$0.isProgressiveFastStart }
            .max(by: { $0.quality < $1.quality })
    }

    func dolbyVisionWarmupVariant() -> PlayVariant? {
        sortedPlayVariants(playVariants)
            .first {
                $0.isPlayable
                    && !$0.isProgressiveFastStart
                    && $0.dynamicRange == .dolbyVision
            }
    }
}
