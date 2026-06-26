import Foundation
import OSLog

extension HomeFeedPreloadCoordinator {
    func logVisiblePreloadChoice(_ candidate: HomeVisiblePreloadCandidate) {
        let score = visiblePreloadRegistry.score(candidate)
        let midY = candidate.frame.map { Double($0.midY) } ?? -1
        PlayerMetricsLog.logger.info(
            "homeVisiblePreloadCandidate bvid=\(candidate.video.bvid, privacy: .public) index=\(candidate.index, privacy: .public) score=\(Double(score), format: .fixed(precision: 1), privacy: .public) midY=\(midY, format: .fixed(precision: 1), privacy: .public)"
        )
    }
}
