import Foundation

extension VideoDetailViewModel {
    func preferredStartupFallbackCandidate(
        in group: [PlayVariant],
        preferredQualities: [Int],
        targetVariant: PlayVariant
    ) -> PlayVariant? {
        for quality in preferredQualities {
            if let candidate = group.first(where: { $0.quality == quality }) {
                PlayerMetricsLog.record(
                    .qualitySupplement,
                    metricsID: detail.bvid,
                    title: detail.title,
                    message: "startupQuality fallback q\(candidate.quality)->q\(targetVariant.quality)"
                )
                return candidate
            }
        }
        if let candidate = group.min(by: { lhs, rhs in
            if lhs.quality != rhs.quality {
                return lhs.quality < rhs.quality
            }
            return (lhs.bandwidth ?? Int.max) < (rhs.bandwidth ?? Int.max)
        }) {
            PlayerMetricsLog.record(
                .qualitySupplement,
                metricsID: detail.bvid,
                title: detail.title,
                message: "startupQuality lowest q\(candidate.quality)->q\(targetVariant.quality)"
            )
            return candidate
        }
        return nil
    }

    nonisolated static func uniqueStartupFallbackQualities(
        startupQuality: Int,
        targetQuality: Int
    ) -> [Int] {
        var seen = Set<Int>()
        let qualityLadder = [127, 126, 125, 120, 116, 112, 80, 74, 64, 32, 16, 6]
        return ([startupQuality, 32, 64, 80, 74, 16, 6] + qualityLadder.reversed())
            .filter { quality in
                quality < targetQuality && seen.insert(quality).inserted
            }
    }
}
