import Foundation

extension VideoDetailViewModel {
    func recordSupplementalPlayURLLoadStarted(preferredQuality: Int?) {
        PlayerMetricsLog.record(
            .qualitySupplement,
            metricsID: detail.bvid,
            title: detail.title,
            message: "start preferred=\(preferredQuality ?? 0)"
        )
    }

    func recordSupplementalPlayURLLoadFailed(_ error: Error) {
        PlayerMetricsLog.record(
            .qualitySupplement,
            metricsID: detail.bvid,
            title: detail.title,
            message: "failed \(error.localizedDescription)"
        )
    }
}
