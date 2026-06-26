import Foundation

extension VideoDetailViewModel {
    func applyPlayableVariantState(
        variants: [PlayVariant],
        source: String
    ) -> (selectedVariant: PlayVariant?, targetVariant: PlayVariant?)? {
        lastPlayURLSource = source
        playURLElapsedMilliseconds = elapsedMilliseconds(since: playURLLoadStartTime)
        failedPlayVariantIDs.removeAll()

        guard !variants.isEmpty else {
            playVariants = []
            selectedPlayVariant = nil
            return nil
        }

        let selectedVariant = preferredDefaultVariant(in: variants)
        let targetVariant = selectedVariant
        playVariants = variants
        selectedPlayVariant = selectedVariant
        logSelectedPlayVariant(selectedVariant, availableVariants: variants, source: source)
        return (selectedVariant, targetVariant)
    }

    func clearSupplementalPlayURLState() {
        cancelPlayURLSupplementTask()
        isSupplementingPlayQualities = false
    }
}
