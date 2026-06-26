import Foundation

extension VideoDetailViewModel {
    func stagedStartupVariant(for target: PlayVariant, in variants: [PlayVariant]) -> PlayVariant? {
        guard let targetAudioURL = target.audioURL,
              target.videoURL != nil
        else { return nil }

        let candidates = sortedPlayVariants(variants)
            .filter {
                $0.isPlayable
                    && $0.id != target.id
                    && $0.audioURL == targetAudioURL
                    && $0.quality < target.quality
                    && $0.dynamicRange == target.dynamicRange
                    && $0.videoStream?.isHardwareDecodingCompatibleVideo == true
                    && $0.videoURL != nil
                    && variantsShareVideoCodecFamily($0, target)
            }
        guard !candidates.isEmpty else { return nil }

        let sameFrameRateCandidates = candidates.filter { variantsShareStartupFrameRateClass($0, target) }
        if let candidate = preferredStagedStartupVariant(
            in: sameFrameRateCandidates,
            qualityOrder: stagedStartupQualityOrder(for: target)
        ) {
            return candidate
        }

        guard variantFrameRate(target) >= 50 else {
            return sameFrameRateCandidates.first
        }

        return preferredStagedStartupVariant(
            in: candidates.filter { !variantsShareStartupFrameRateClass($0, target) },
            qualityOrder: stagedStartupQualityOrder(for: target, allowsFrameRateFallback: true)
        )
    }

    func preferredStagedStartupVariant(
        in candidates: [PlayVariant],
        qualityOrder: [Int]
    ) -> PlayVariant? {
        guard !candidates.isEmpty else { return nil }
        for quality in qualityOrder {
            if let candidate = candidates.first(where: { $0.quality == quality }) {
                return candidate
            }
        }
        return candidates.first
    }

    func stagedStartupQualityOrder(
        for target: PlayVariant,
        allowsFrameRateFallback: Bool = false
    ) -> [Int] {
        stagedStartupQualityOrder(
            for: target,
            startupCeiling: adaptiveStartupQualityCeiling ?? Int.max,
            allowsFrameRateFallback: allowsFrameRateFallback
        )
    }
}
