import Foundation

extension VideoDetailViewModel {
    func recordStagedStartupUpgradeSkipped(
        reason: String,
        startupVariant: PlayVariant,
        targetVariant: PlayVariant
    ) {
        PlayerMetricsLog.record(
            .qualitySupplement,
            metricsID: detail.bvid,
            title: detail.title,
            message: "stagedStartup skip reason=\(reason) q\(startupVariant.quality)->q\(targetVariant.quality)"
        )
    }
}
