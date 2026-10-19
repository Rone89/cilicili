import Foundation

@MainActor
struct HomeFeedSnapshotCoordinator {
    let libraryStore: LibraryStore
    let sessionStore: SessionStore
    let storage: any HomeFeedSnapshotStoring

    func context(mode: HomeFeedMode) -> HomeFeedSnapshotContext {
        HomeFeedSnapshotContext(
            mode: mode,
            guestModeEnabled: libraryStore.guestModeEnabled,
            recommendSource: libraryStore.homeRecommendFeedSourcePreference,
            accountIdentityKey: sessionStore.recommendCacheIdentityKey(
                guestModeEnabled: libraryStore.guestModeEnabled
            )
        )
    }

    func load(mode: HomeFeedMode) async -> HomeFeedSnapshotRestore? {
        let requestedContext = context(mode: mode)
        let credentialVersion = sessionStore.playbackCredentialVersion
        let snapshot = await storage.load(context: requestedContext)
        guard !Task.isCancelled,
              credentialVersion == sessionStore.playbackCredentialVersion,
              requestedContext == context(mode: mode) else { return nil }
        return snapshot
    }

    func save(videos: [VideoItem], mode: HomeFeedMode, lastSeenMarkerIndex: Int? = nil) {
        storage.save(videos: videos, context: context(mode: mode), lastSeenMarkerIndex: lastSeenMarkerIndex)
    }
}
