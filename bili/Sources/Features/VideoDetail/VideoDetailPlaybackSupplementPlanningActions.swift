import Foundation

extension VideoDetailViewModel {
    func replacingVariant(
        in variants: [PlayVariant],
        matching id: String,
        with replacement: PlayVariant
    ) -> [PlayVariant] {
        variants.map { $0.id == id ? replacement : $0 }
    }

    func scheduleSupplementalTargetQualityLoadIfNeeded(
        variants: [PlayVariant],
        cid: Int?,
        page: Int?
    ) {
        guard let cid,
              needsSupplementalTargetQuality(variants)
        else { return }
        scheduleSupplementalPlayURLLoad(
            cid: cid,
            page: page,
            waitsForFirstFrame: true,
            startDelay: 0.12
        )
    }

    private func shouldSupplementPlayQualities(for variants: [PlayVariant]) -> Bool {
        false
    }

    private func needsSupplementalTargetQuality(_ variants: [PlayVariant]) -> Bool {
        guard let preferredQuality = targetPlaybackPreferredQuality else { return false }
        let playableVariants = variants.filter(\.isPlayable)
        guard !playableVariants.isEmpty else { return false }
        if [116, 74].contains(preferredQuality) {
            return !playableVariants.contains {
                $0.quality == preferredQuality && variantFrameRate($0) >= 50
            }
        }
        return !playableVariants.contains { $0.quality == preferredQuality }
    }

    private func playVariantsNeedSupplementalFrameRateUpgrade(_ variants: [PlayVariant]) -> Bool {
        let playableVariants = variants.filter(\.isPlayable)
        guard !playableVariants.isEmpty else { return false }
        guard let preferredQuality = libraryStore.preferredVideoQuality else { return false }
        guard [116, 74].contains(preferredQuality) else { return false }
        return !playableVariants.contains {
            $0.quality == preferredQuality && variantFrameRate($0) >= 50
        }
    }
}
