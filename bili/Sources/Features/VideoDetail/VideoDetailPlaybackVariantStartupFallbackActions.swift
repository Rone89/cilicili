import Foundation

extension VideoDetailViewModel {
    func fallbackAutomaticStartupVariant(
        in variants: [PlayVariant],
        targetVariant: PlayVariant,
        startupQuality: Int
    ) -> PlayVariant? {
        let candidates = sortedPlayVariants(variants)
            .filter {
                $0.isPlayable
                    && $0.id != targetVariant.id
                    && $0.quality < targetVariant.quality
                    && $0.dynamicRange == targetVariant.dynamicRange
                    && $0.videoURL != nil
                    && $0.videoStream?.isHardwareDecodingCompatibleVideo == true
            }
        guard !candidates.isEmpty else { return nil }

        let preferredAudioURL = targetVariant.audioURL
        let preferredGroups = [
            candidates.filter {
                $0.audioURL == preferredAudioURL
                    && variantsShareVideoCodecFamily($0, targetVariant)
            },
            candidates.filter { $0.audioURL == preferredAudioURL },
            candidates
        ]
        let preferredQualities = Self.uniqueStartupFallbackQualities(
            startupQuality: startupQuality,
            targetQuality: targetVariant.quality
        )

        for group in preferredGroups where !group.isEmpty {
            if let preferredCandidate = preferredStartupFallbackCandidate(
                in: group,
                preferredQualities: preferredQualities,
                targetVariant: targetVariant
            ) {
                return preferredCandidate
            }
        }
        return nil
    }

}
