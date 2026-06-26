import Foundation

extension VideoDetailViewModel {
    func fastStartVariant(for target: PlayVariant?, in variants: [PlayVariant]) -> PlayVariant? {
        guard let target else { return nil }
        if let reason = startupStagedStartupDisabledReason(for: target) {
            logStagedStartupDecision(
                "disabled reason=\(reason) target=q\(target.quality) available=\(Self.qualitySummary(variants))"
            )
            return target
        }
        guard let startup = stagedStartupVariant(for: target, in: variants) else {
            logStagedStartupDecision(
                "disabled reason=noCandidate target=q\(target.quality) available=\(Self.qualitySummary(variants))"
            )
            return target
        }
        logStagedStartupDecision(
            "selected q\(startup.quality)->q\(target.quality) targetFPS=\(Self.formattedFrameRate(variantFrameRate(target))) startupFPS=\(Self.formattedFrameRate(variantFrameRate(startup)))"
        )
        PlayerMetricsLog.record(
            .qualitySupplement,
            metricsID: detail.bvid,
            title: detail.title,
            message: "stagedStartup selected q\(startup.quality)->q\(target.quality)"
        )
        return startup
    }
}
