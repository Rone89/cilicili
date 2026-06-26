import Foundation

extension HomeGuestRecommendPageAccumulator {
    mutating func append(_ page: [VideoItem]) {
        for video in page where !video.id.isEmpty {
            appendFallbackIfNeeded(video)
            appendFreshIfNeeded(video)
        }
    }

    func resolvedPage(lastRawPage: [VideoItem]) -> [VideoItem] {
        guard !freshVideos.isEmpty else {
            return fallbackVideos.isEmpty ? lastRawPage : fallbackVideos
        }
        let targetCount = max(minimumFreshCount, min(20, fallbackVideos.count))
        guard freshVideos.count < targetCount else {
            return freshVideos
        }

        var merged = freshVideos
        var mergedIDs = Set(freshVideos.map(\.id))
        for video in fallbackVideos where mergedIDs.insert(video.id).inserted {
            merged.append(video)
            if merged.count >= targetCount {
                break
            }
        }
        return merged
    }

    mutating func appendFallbackIfNeeded(_ video: VideoItem) {
        guard !excludedIDs.contains(video.id),
              fallbackIDs.insert(video.id).inserted
        else { return }
        fallbackVideos.append(video)
    }

    mutating func appendFreshIfNeeded(_ video: VideoItem) {
        guard !exposureIDs.contains(video.id),
              freshIDs.insert(video.id).inserted
        else { return }
        freshVideos.append(video)
        exposureIDs.insert(video.id)
    }
}
