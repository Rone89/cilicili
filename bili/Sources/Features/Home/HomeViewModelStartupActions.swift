import Foundation

extension HomeViewModel {
    func loadInitial() async {
        guard videos.isEmpty else { return }
        updateFeed([])
        state = .loading
        await refresh(resetCursor: true)
    }

    func switchMode(_ newMode: HomeFeedMode) async {
        guard mode != newMode else { return }
        mode = newMode
        updateFeed([])
        restoreCachedVideosIfAvailable()
        await refresh(resetCursor: true)
    }

    func reloadForRecommendContextChange() async {
        guard mode == .recommend else { return }
        updateFeed([])
        restoreCachedVideosIfAvailable()
        await refresh(resetCursor: true)
    }
}
