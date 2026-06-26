import Foundation

@MainActor
struct HomeFeedSnapshotCoordinator {
    let libraryStore: LibraryStore

    func load(mode: HomeFeedMode) -> [VideoItem]? {
        HomeFeedSnapshotCache.load(
            mode: mode,
            guestModeEnabled: libraryStore.guestModeEnabled,
            recommendSource: libraryStore.homeRecommendFeedSourcePreference
        )
    }

    func save(videos: [VideoItem], mode: HomeFeedMode) {
        HomeFeedSnapshotCache.save(
            videos: Array(videos.prefix(48)),
            mode: mode,
            guestModeEnabled: libraryStore.guestModeEnabled,
            recommendSource: libraryStore.homeRecommendFeedSourcePreference
        )
    }
}
