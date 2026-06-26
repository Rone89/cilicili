import SwiftUI

enum HomeVisiblePreloadScorer {
    static func isVisibleEnough(
        _ candidate: HomeVisiblePreloadCandidate,
        screenHeight: CGFloat
    ) -> Bool {
        guard let frame = candidate.frame else { return true }
        let topBound = screenHeight * 0.12
        let bottomBound = screenHeight * 0.86
        let visibleHeight = max(0, min(frame.maxY, bottomBound) - max(frame.minY, topBound))
        let ratio = visibleHeight / max(frame.height, 1)
        return ratio >= 0.18
    }

    static func shouldSort(
        _ lhs: HomeVisiblePreloadCandidate,
        before rhs: HomeVisiblePreloadCandidate,
        screenHeight: CGFloat
    ) -> Bool {
        let lhsScore = score(lhs, screenHeight: screenHeight)
        let rhsScore = score(rhs, screenHeight: screenHeight)
        if abs(lhsScore - rhsScore) > 0.01 {
            return lhsScore < rhsScore
        }
        if lhs.index != rhs.index {
            return lhs.index < rhs.index
        }
        return lhs.sequence < rhs.sequence
    }

    static func score(
        _ candidate: HomeVisiblePreloadCandidate,
        screenHeight: CGFloat
    ) -> CGFloat {
        guard let frame = candidate.frame else {
            return 10_000 + CGFloat(candidate.index)
        }

        let topBound = screenHeight * 0.12
        let bottomBound = screenHeight * 0.86
        let visibleHeight = max(0, min(frame.maxY, bottomBound) - max(frame.minY, topBound))
        let visibilityRatio = min(max(visibleHeight / max(frame.height, 1), 0), 1)
        let targetY = screenHeight * 0.38
        var score = abs(frame.midY - targetY)
        if frame.midY > screenHeight * 0.70 {
            score += screenHeight * 0.40
        }
        if frame.minY < topBound {
            score += screenHeight * 0.15
        }
        score -= visibilityRatio * 40
        score += CGFloat(candidate.index) * 0.01
        return score
    }
}
