import Foundation

extension HomeFeedPageCoordinator {
    func fetchFreshPage(
        for mode: HomeFeedMode,
        replacing previousIDs: [String],
        minimumFreshCount: Int? = nil
    ) async throws -> [VideoItem] {
        switch mode {
        case .popular:
            return try await api.fetchPopularVideos(page: popularPage)
        case .recommend:
            if usesNativeAppRecommendSource(for: mode) {
                return try await api.fetchRecommendFeed(freshIndex: freshIndex)
            }
            if usesGuestRecommendDiversity(for: mode) {
                return try await fetchGuestRecommendPage(
                    excluding: Set(previousIDs),
                    minimumFreshCount: minimumFreshCount ?? (previousIDs.isEmpty ? 14 : 10),
                    maximumAttempts: 5
                )
            }
            if let minimumFreshCount {
                return try await fetchUniqueRecommendRefreshPage(
                    excluding: Set(previousIDs),
                    minimumFreshCount: minimumFreshCount,
                    maximumAttempts: 5
                )
            }
            var lastPage = [VideoItem]()
            for attempt in 0..<5 {
                if attempt > 0 {
                    freshIndex += 1
                }
                let page = try await api.fetchRecommendFeed(freshIndex: freshIndex)
                lastPage = page
                if HomeFeedVisibleChangeDetector.hasVisibleChange(in: page, comparedTo: previousIDs) {
                    return page
                }
            }
            return lastPage
        }
    }
}
