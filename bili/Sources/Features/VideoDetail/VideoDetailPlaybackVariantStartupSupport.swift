import Foundation

extension VideoDetailViewModel {
    func automaticStartupVariant(in variants: [PlayVariant], targetVariant: PlayVariant?) -> PlayVariant? {
        guard !didSelectPlayVariantManually,
              let startupQuality = adaptiveStartupPreferredQuality,
              let targetVariant,
              startupQuality < targetVariant.quality
        else { return nil }
        guard let startupVariant = preferredDefaultVariant(
            in: variants,
            preferredQuality: startupQuality
        ) ?? fallbackAutomaticStartupVariant(
            in: variants,
            targetVariant: targetVariant,
            startupQuality: startupQuality
        ) else { return nil }
        guard startupVariant.id != targetVariant.id,
              startupVariant.isPlayable,
              variant(targetVariant, isBetterThan: startupVariant)
        else { return nil }
        PlayerMetricsLog.record(
            .qualitySupplement,
            metricsID: detail.bvid,
            title: detail.title,
            message: "startupQuality selected q\(startupVariant.quality)->q\(targetVariant.quality)"
        )
        return startupVariant
    }
}
