import Foundation

extension HomeViewModel {
    func refreshFromUserPull() async {
        guard !isRefreshing else { return }
        let now = Date()
        if let lastUserRefreshDate,
           now.timeIntervalSince(lastUserRefreshDate) < 1.0 {
            return
        }
        lastUserRefreshDate = now
        isUserRefreshing = true
        defer {
            isUserRefreshing = false
        }
        await refresh(preservingExistingRecommendations: true)
    }
}
