import Foundation

@MainActor
struct HomeFeedSnapshotCoordinator {
    let libraryStore: LibraryStore
    let sessionStore: SessionStore

    func load(mode: HomeFeedMode) -> [VideoItem]? {
        HomeFeedSnapshotCache.load(
            mode: mode,
            guestModeEnabled: libraryStore.guestModeEnabled,
            recommendSource: libraryStore.homeRecommendFeedSourcePreference,
            accountIdentityKey: sessionStore.recommendCacheIdentityKey(
                guestModeEnabled: libraryStore.guestModeEnabled
            )
        )
    }

    func save(videos: [VideoItem], mode: HomeFeedMode) {
        HomeFeedSnapshotCache.save(
            videos: Array(videos.prefix(48)),
            mode: mode,
            guestModeEnabled: libraryStore.guestModeEnabled,
            recommendSource: libraryStore.homeRecommendFeedSourcePreference,
            accountIdentityKey: sessionStore.recommendCacheIdentityKey(
                guestModeEnabled: libraryStore.guestModeEnabled
            )
        )
    }
}
