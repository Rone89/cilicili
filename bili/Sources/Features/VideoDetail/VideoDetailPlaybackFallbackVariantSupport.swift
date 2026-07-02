import Foundation

extension VideoDetailViewModel {
    func playbackFallbackVariant(excluding failedVariant: PlayVariant) -> PlayVariant? {
        if failedVariant.dynamicRange.isHDR,
           let hdrFallback = sdrPlaybackFallbackVariant(excluding: failedVariant) {
            return hdrFallback
        }

        let candidates = sortedPlayVariants(playVariants)
            .filter {
                $0.isPlayable
                    && $0.id != failedVariant.id
                    && !failedPlayVariantIDs.contains($0.id)
            }
        guard !candidates.isEmpty else { return nil }

        let lowerOrEqualQuality = candidates
            .filter { $0.quality <= failedVariant.quality }
        if let fallback = lowerOrEqualQuality
            .first(where: { !$0.isProgressiveFastStart }) {
            return fallback
        }
        return lowerOrEqualQuality.first
            ?? candidates.first(where: { !$0.isProgressiveFastStart })
            ?? candidates.first
    }

    private func sdrPlaybackFallbackVariant(excluding failedVariant: PlayVariant) -> PlayVariant? {
        let candidates = sortedPlayVariants(playVariants)
            .filter {
                $0.isPlayable
                    && $0.id != failedVariant.id
                    && !failedPlayVariantIDs.contains($0.id)
                    && $0.dynamicRange == .sdr
                    && !$0.isProgressiveFastStart
            }
        let preferredFallbackQualities = [116, 112, 80, 120, 74, 64, 32]
        for quality in preferredFallbackQualities {
            if let variant = candidates.first(where: { $0.quality == quality }) {
                return variant
            }
        }
        return candidates.first
            ?? sortedPlayVariants(playVariants).first {
                $0.isPlayable
                    && $0.id != failedVariant.id
                    && $0.dynamicRange == .sdr
            }
    }
}
