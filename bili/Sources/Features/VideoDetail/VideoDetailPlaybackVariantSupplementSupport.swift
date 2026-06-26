import Foundation

extension VideoDetailViewModel {
    func mergedSupplementalVariants(
        _ variants: [PlayVariant],
        preserving currentVariant: PlayVariant?
    ) -> [PlayVariant] {
        let sortedVariants = sortedPlayVariants(variants)
        guard let currentVariant,
              currentVariant.isPlayable,
              !sortedVariants.contains(where: { $0.id == currentVariant.id })
        else {
            return sortedVariants
        }
        return [currentVariant] + sortedVariants
    }

    func shouldAutoUpgradeSupplementalVariant(from currentVariant: PlayVariant?) -> Bool {
        // Keep supplemental quality loads as menu/data updates only. Switching after first
        // frame makes some videos visibly jump from 480P to the target quality.
        false
    }
}
