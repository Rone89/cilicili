import Foundation

extension VideoDetailViewModel {
    func preferredDefaultVariant(in variants: [PlayVariant]) -> PlayVariant? {
        preferredDefaultVariant(in: variants, preferredQuality: nil)
    }

    func preferredDefaultVariant(in variants: [PlayVariant], preferredQuality: Int?) -> PlayVariant? {
        let playableVariants = sortedPlayVariants(variants).filter(\.isPlayable)
        let playbackEnvironment = PlaybackEnvironment.current

        if let preferredVariant = storedPreferredVariant(in: playableVariants, preferredQuality: preferredQuality) {
            return preferredVariant
        }
        if preferredQuality != nil {
            return nil
        }

        if let defaultVariant = playableVariants.first(where: { $0.quality == LibraryStore.defaultPreferredVideoQuality }) {
            return defaultVariant
        }

        let preferredQualities = playbackEnvironment.preferredQualityLadder
        for quality in preferredQualities {
            if let variant = playableVariants.first(where: { $0.quality == quality }) {
                return variant
            }
        }

        return playableVariants.first ?? variants.first
    }

    private func storedPreferredVariant(in playableVariants: [PlayVariant], preferredQuality: Int?) -> PlayVariant? {
        guard let preferredQuality = preferredQuality
                ?? (didSelectPlayVariantManually
                    ? manuallySelectedPlayVariantQuality
                    : targetPlaybackPreferredQuality)
        else { return nil }
        let sortedVariants = sortedPlayVariants(playableVariants)
        if let exactVariant = sortedVariants.first(where: { $0.quality == preferredQuality }) {
            return exactVariant
        }

        guard let preferredIndex = LibraryStore.supportedVideoQualities.firstIndex(of: preferredQuality) else {
            return nil
        }
        let fallbackQualities = LibraryStore.supportedVideoQualities.dropFirst(preferredIndex + 1)
        for quality in fallbackQualities {
            if let variant = sortedVariants.first(where: { $0.quality == quality }) {
                return variant
            }
        }
        return nil
    }
}
