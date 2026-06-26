import Foundation

extension HomeFeedSnapshotCache {
    static func snapshotURL(
        mode: HomeFeedMode,
        guestModeEnabled: Bool,
        recommendSource: HomeRecommendFeedSourcePreference
    ) -> URL {
        let source = mode == .recommend ? recommendSource.rawValue : "default"
        return directoryURL.appending(
            path: "\(mode.rawValue)-source-\(source)-guest-\(guestModeEnabled ? "1" : "0").json"
        )
    }

    static func legacyKey(mode: HomeFeedMode, guestModeEnabled: Bool) -> String {
        "cc.bili.home.snapshot.\(mode.rawValue).guest-\(guestModeEnabled ? "1" : "0")"
    }
}
