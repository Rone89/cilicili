import Foundation

extension HomeViewModel {
    func refresh(
        resetCursor shouldResetCursor: Bool = false,
        preservingExistingRecommendations shouldPreserveExistingRecommendations: Bool = false
    ) async {
        let previousVideos = videos
        let previousIDs = previousVideos.map(\.id)
        requestRevision += 1
        let revision = requestRevision
        state = .loading
        isRefreshing = true
        defer {
            if revision == requestRevision {
                isRefreshing = false
            }
        }
        if shouldResetCursor {
            pageCoordinator.resetCursor(for: mode)
        } else {
            pageCoordinator.advanceRefreshCursor(for: mode)
        }
        do {
            let refreshedVideos = try await pageCoordinator.fetchFreshPage(
                for: mode,
                replacing: previousIDs,
                minimumFreshCount: shouldPreserveExistingRecommendations ? Self.userRefreshRecommendationCount : nil
            )
            guard revision == requestRevision else { return }
            if previousVideos.isEmpty {
                await mediaPreloadCoordinator.prewarmInitialImagesBeforePublishing(refreshedVideos)
            }
            replaceVideos(
                refreshedVideos,
                previousVideos: previousVideos,
                preservingExistingRecommendations: shouldPreserveExistingRecommendations
            )
            snapshotCoordinator.save(videos: videos, mode: mode)
            state = .loaded
        } catch {
            guard revision == requestRevision else { return }
            state = .failed(error.localizedDescription)
        }
    }
}
