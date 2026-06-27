import Foundation

enum HomeFeedMergePolicy {
    static func refreshedVideos(
        fresh: [VideoItem],
        previousVideos: [VideoItem],
        mode: HomeFeedMode,
        preservesExistingRecommendations: Bool,
        usesNativeReplacement: Bool = false
    ) -> [VideoItem] {
        if usesNativeReplacement {
            return fresh
        }
        if preservesExistingRecommendations {
            return prependFreshVideos(fresh, to: previousVideos, mode: mode)
        }
        return mergedRefreshVideos(fresh, previousVideos: previousVideos, mode: mode)
    }

    static func uniqueAppendVideos(
        _ more: [VideoItem],
        to videos: [VideoItem]
    ) -> [VideoItem] {
        let existing = Set(videos.map(\.id))
        return more.filter { !existing.contains($0.id) }
    }

    private static func mergedRefreshVideos(
        _ fresh: [VideoItem],
        previousVideos: [VideoItem],
        mode: HomeFeedMode
    ) -> [VideoItem] {
        guard mode == .recommend, !fresh.isEmpty, !previousVideos.isEmpty else {
            return fresh
        }
        var seen = Set(fresh.map(\.id))
        let retainedTail = previousVideos
            .prefix(50)
            .filter { seen.insert($0.id).inserted }
        return fresh + retainedTail
    }

    private static func prependFreshVideos(
        _ fresh: [VideoItem],
        to previousVideos: [VideoItem],
        mode: HomeFeedMode
    ) -> [VideoItem] {
        guard mode == .recommend, !fresh.isEmpty, !previousVideos.isEmpty else {
            return fresh.isEmpty ? previousVideos : fresh
        }
        var seen = Set(fresh.map(\.id))
        let retainedVideos = previousVideos.filter { seen.insert($0.id).inserted }
        return fresh + retainedVideos
    }
}
