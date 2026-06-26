import SwiftUI

extension HomeVisiblePreloadRegistry {
    mutating func trimCandidatesIfNeeded() {
        guard visiblePreloadCandidates.count > visibleCandidateLimit else { return }
        let kept = Set(
            visiblePreloadCandidates.values
                .sorted { lhs, rhs in
                    if lhs.index != rhs.index {
                        return lhs.index < rhs.index
                    }
                    return lhs.sequence < rhs.sequence
                }
                .prefix(visibleCandidateLimit)
                .map { $0.video.bvid }
        )
        visiblePreloadCandidates = visiblePreloadCandidates.filter { kept.contains($0.key) }
    }
}
