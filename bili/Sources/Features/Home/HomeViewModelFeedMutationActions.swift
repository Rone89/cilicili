import Foundation

extension HomeViewModel {
    func replaceVideos(
        _ newVideos: [VideoItem],
        previousVideos: [VideoItem],
        preservingExistingRecommendations shouldPreserveExistingRecommendations: Bool = false
    ) {
        let mergedFeed = HomeFeedMergePolicy.refreshedFeed(
            fresh: newVideos,
            previousVideos: previousVideos,
            mode: mode,
            preservesExistingRecommendations: shouldPreserveExistingRecommendations,
            usesNativeReplacement: pageCoordinator.usesNativeAppRecommendSource(for: mode)
        )
        updateFeed(mergedFeed.videos)
        updateLastSeenMarkerIndex(mergedFeed.lastSeenMarkerIndex)
        exposureRecorder.recordIfNeeded(mergedFeed.videos, mode: mode)
        Task {
            await ResourceLoadingForegroundPriorityGate.shared.beginFirstScreenPriorityWindow(for: .home)
        }
        mediaPreloadCoordinator.scheduleImagePrefetch(for: mergedFeed.videos)
        mediaPreloadCoordinator.schedulePlaybackPreload(for: newVideos, initialDelay: 0.75)
        scheduleRecommendMetadataHydration(
            for: mergedFeed.videos,
            revision: requestRevision,
            reason: "refresh"
        )
    }

    func appendUnique(_ more: [VideoItem]) {
        let unique = HomeFeedMergePolicy.uniqueAppendVideos(more, to: videos)
        guard !unique.isEmpty else { return }
        updateFeed(videos + unique)
        exposureRecorder.recordIfNeeded(unique, mode: mode)
        updateLastSeenMarkerIndex(lastSeenMarkerIndex)
        snapshotCoordinator.save(
            videos: videos,
            mode: mode,
            lastSeenMarkerIndex: lastSeenMarkerIndex
        )
        mediaPreloadCoordinator.scheduleImagePrefetch(for: Array(unique.prefix(8)))
        mediaPreloadCoordinator.schedulePlaybackPreload(for: unique, initialDelay: 1.2)
        scheduleRecommendMetadataHydration(
            for: unique,
            revision: requestRevision,
            reason: "append"
        )
    }

    func restoreCachedVideosIfAvailable() async {
        guard videos.isEmpty else { return }
        let requestedMode = mode
        let revision = requestRevision
        guard let snapshot = await snapshotCoordinator.load(mode: requestedMode),
              !Task.isCancelled, revision == requestRevision, mode == requestedMode,
              videos.isEmpty, !snapshot.videos.isEmpty
        else { return }
        updateFeed(snapshot.videos)
        updateLastSeenMarkerIndex(snapshot.lastSeenMarkerIndex)
        state = .loaded
        Task {
            await ResourceLoadingForegroundPriorityGate.shared.beginFirstScreenPriorityWindow(for: .home)
        }
        mediaPreloadCoordinator.scheduleImagePrefetch(for: Array(snapshot.videos.prefix(8)))
    }

}
