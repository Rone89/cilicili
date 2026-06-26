import Foundation

extension HomeViewModel {
    func replaceVideos(
        _ newVideos: [VideoItem],
        previousVideos: [VideoItem],
        preservingExistingRecommendations shouldPreserveExistingRecommendations: Bool = false
    ) {
        let mergedVideos = HomeFeedMergePolicy.refreshedVideos(
            fresh: newVideos,
            previousVideos: previousVideos,
            mode: mode,
            preservesExistingRecommendations: shouldPreserveExistingRecommendations
        )
        updateFeed(mergedVideos)
        exposureRecorder.recordIfNeeded(mergedVideos, mode: mode)
        mediaPreloadCoordinator.scheduleImagePrefetch(for: mergedVideos)
        mediaPreloadCoordinator.schedulePlaybackPreload(for: newVideos, initialDelay: 0.75)
    }

    func appendUnique(_ more: [VideoItem]) {
        let unique = HomeFeedMergePolicy.uniqueAppendVideos(more, to: videos)
        guard !unique.isEmpty else { return }
        updateFeed(videos + unique)
        exposureRecorder.recordIfNeeded(unique, mode: mode)
        snapshotCoordinator.save(videos: videos, mode: mode)
        mediaPreloadCoordinator.scheduleImagePrefetch(for: Array(unique.prefix(8)))
        mediaPreloadCoordinator.schedulePlaybackPreload(for: unique, initialDelay: 1.2)
    }

    func restoreCachedVideosIfAvailable() {
        guard videos.isEmpty else { return }
        guard let cachedVideos = snapshotCoordinator.load(mode: mode),
              !cachedVideos.isEmpty
        else { return }
        updateFeed(cachedVideos)
        state = .loaded
        mediaPreloadCoordinator.scheduleImagePrefetch(for: Array(cachedVideos.prefix(8)))
    }

}
