import Foundation

extension VideoDetailViewModel {
    func fastStartVariant(for target: PlayVariant?, in variants: [PlayVariant]) -> PlayVariant? {
        guard let target else { return nil }
        logStagedStartupDecision(
            "disabled reason=qualityPriority target=q\(target.quality) available=\(Self.qualitySummary(variants))"
        )
        return target
    }
}
