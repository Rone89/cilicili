import SwiftUI

extension HomeFeedPreloadCoordinator {
    func scheduleVisiblePreload(
        delay: Duration,
        context: HomeFeedPreloadContext
    ) {
        visiblePreloadDebouncer.schedule(delay: delay) { [weak self] in
            guard let self else { return }
            let limit = min(3, context.playbackAdaptationProfile.backgroundRoutePlanPreloadLimit)
            guard limit > 0 else { return }
            let candidates = self.bestVisiblePreloadCandidates(limit: limit)
            guard !candidates.isEmpty else { return }
            for (index, candidate) in candidates.enumerated() {
                self.logVisiblePreloadChoice(candidate)
                self.beginVisiblePreloadIfNeeded(
                    for: candidate.video,
                    context: context,
                    isPrimary: index == 0
                )
            }
        }
    }

    func bestVisiblePreloadCandidate() -> HomeVisiblePreloadCandidate? {
        visiblePreloadRegistry.bestCandidate()
    }

    func bestVisiblePreloadCandidates(limit: Int) -> [HomeVisiblePreloadCandidate] {
        visiblePreloadRegistry.bestCandidates(limit: limit)
    }
}
