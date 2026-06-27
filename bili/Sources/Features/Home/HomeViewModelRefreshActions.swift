import Foundation

extension HomeViewModel {
    func refresh(
        resetCursor shouldResetCursor: Bool = false,
        preservingExistingRecommendations shouldPreserveExistingRecommendations: Bool = false
    ) async {
        let usesNativeAppRecommend = pageCoordinator.usesNativeAppRecommendSource(for: mode)
        let preservesExistingRecommendations = shouldPreserveExistingRecommendations && !usesNativeAppRecommend
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
        if shouldResetCursor || usesNativeAppRecommend {
            pageCoordinator.resetCursor(for: mode)
        } else {
            pageCoordinator.advanceRefreshCursor(for: mode)
        }
        do {
            let refreshedVideos = try await pageCoordinator.fetchFreshPage(
                for: mode,
                replacing: previousIDs,
                minimumFreshCount: preservesExistingRecommendations ? Self.userRefreshRecommendationCount : nil
            )
            guard revision == requestRevision else { return }
            if previousVideos.isEmpty {
                await mediaPreloadCoordinator.prewarmInitialImagesBeforePublishing(refreshedVideos)
            }
            replaceVideos(
                refreshedVideos,
                previousVideos: previousVideos,
                preservingExistingRecommendations: preservesExistingRecommendations
            )
            snapshotCoordinator.save(videos: videos, mode: mode)
            state = .loaded
        } catch {
            guard revision == requestRevision else { return }
            state = .failed(error.localizedDescription)
        }
    }
}
