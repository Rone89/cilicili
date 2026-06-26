import Foundation

extension HomeFeedSnapshotCache {
    static func pruneExpiredSnapshots(now: Date = Date()) {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        for url in urls {
            let modifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modifiedAt, now.timeIntervalSince(modifiedAt) > maxAge * 2 {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
