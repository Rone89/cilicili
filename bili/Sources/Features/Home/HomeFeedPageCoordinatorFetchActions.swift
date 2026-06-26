import Foundation

extension HomeFeedPageCoordinator {
    func fetchCurrentPage(
        for mode: HomeFeedMode,
        existingIDs: Set<String>
    ) async throws -> [VideoItem] {
        switch mode {
        case .recommend:
            if usesGuestRecommendDiversity(for: mode) {
                return try await fetchGuestRecommendPage(
                    excluding: existingIDs,
                    minimumFreshCount: 10,
                    maximumAttempts: 4
                )
            }
            return try await api.fetchRecommendFeed(freshIndex: freshIndex)
        case .popular:
            return try await api.fetchPopularVideos(page: popularPage)
        }
    }
}
