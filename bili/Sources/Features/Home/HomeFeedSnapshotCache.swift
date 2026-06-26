import Foundation

enum HomeFeedSnapshotCache {
    static let maxAge: TimeInterval = 8 * 60 * 60
    static let directoryURL = URL.cachesDirectory.appending(
        path: "HomeFeedSnapshots",
        directoryHint: .isDirectory
    )

    static func load(
        mode: HomeFeedMode,
        guestModeEnabled: Bool,
        recommendSource: HomeRecommendFeedSourcePreference
    ) -> [VideoItem]? {
        if let snapshot = loadDiskSnapshot(
            mode: mode,
            guestModeEnabled: guestModeEnabled,
            recommendSource: recommendSource
        ) {
            return snapshot.videos.map(\.videoItem)
        }
        guard let data = UserDefaults.standard.data(forKey: legacyKey(mode: mode, guestModeEnabled: guestModeEnabled)),
              let snapshot = try? JSONDecoder().decode(HomeFeedSnapshot.self, from: data),
              Date().timeIntervalSince(snapshot.savedAt) < maxAge
        else { return nil }
        save(snapshot: snapshot, mode: mode, guestModeEnabled: guestModeEnabled, recommendSource: recommendSource)
        UserDefaults.standard.removeObject(forKey: legacyKey(mode: mode, guestModeEnabled: guestModeEnabled))
        return snapshot.videos.map(\.videoItem)
    }

    static func save(
        videos: [VideoItem],
        mode: HomeFeedMode,
        guestModeEnabled: Bool,
        recommendSource: HomeRecommendFeedSourcePreference
    ) {
        let snapshot = HomeFeedSnapshot(
            savedAt: Date(),
            videos: videos.map(HomeFeedCachedVideo.init(video:))
        )
        save(snapshot: snapshot, mode: mode, guestModeEnabled: guestModeEnabled, recommendSource: recommendSource)
    }

}
