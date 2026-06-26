import SwiftUI

extension HomeVisiblePreloadRegistry {
    func bestCandidate() -> HomeVisiblePreloadCandidate? {
        bestCandidates(limit: 1).first
    }

    func bestCandidates(limit: Int) -> [HomeVisiblePreloadCandidate] {
        guard limit > 0 else { return [] }
        return visiblePreloadCandidates.values
            .filter { candidate in
                let bvid = candidate.video.bvid
                return !bvid.isEmpty
                    && !visiblePreloadVideos.contains(bvid)
                    && !recentVisiblePreloadVideos.contains(bvid)
                    && HomeVisiblePreloadScorer.isVisibleEnough(
                        candidate,
                        screenHeight: viewportHeight
                    )
            }
            .sorted {
                HomeVisiblePreloadScorer.shouldSort(
                    $0,
                    before: $1,
                    screenHeight: viewportHeight
                )
            }
            .prefix(limit)
            .map { $0 }
    }

    func canBeginPreload(for bvid: String, routePlanPreloadLimit: Int) -> Bool {
        let limit = max(0, min(routePlanPreloadLimit, visibleCandidateLimit))
        return !bvid.isEmpty
            && !visiblePreloadVideos.contains(bvid)
            && !recentVisiblePreloadVideos.contains(bvid)
            && visiblePreloadVideos.count < limit
            && limit > 0
    }
}
