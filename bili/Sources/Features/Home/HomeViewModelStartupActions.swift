import Foundation

extension HomeViewModel {
    func loadInitial() async {
        guard videos.isEmpty else { return }
        updateLastSeenMarkerIndex(nil)
        updateFeed([])
        restoreCachedVideosIfAvailable()
        if videos.isEmpty {
            state = .loading
        }
        await refresh(resetCursor: true)
    }

    func switchMode(_ newMode: HomeFeedMode) async {
        guard mode != newMode else { return }
        mode = newMode
        updateLastSeenMarkerIndex(nil)
        updateFeed([])
        restoreCachedVideosIfAvailable()
        await refresh(resetCursor: true)
    }

    func reloadForRecommendContextChange() async {
        guard mode == .recommend else { return }
        updateLastSeenMarkerIndex(nil)
        updateFeed([])
        restoreCachedVideosIfAvailable()
        await refresh(resetCursor: true)
    }
}
