import Foundation

extension HomeFeedMediaPreloadCoordinator {
    func scheduleImagePrefetch(for videos: [VideoItem]) {
        imagePrefetchTask?.cancel()
        let environment = PlaybackEnvironment.current
        let prefetchLimit = environment.shouldPreferConservativePlayback ? 4 : 5
        let prefetchPlan = HomeFeedImagePrefetchPlan.make(
            for: videos,
            layout: libraryStore.homeFeedLayout,
            limit: prefetchLimit
        )

        guard !prefetchPlan.coverSources.isEmpty || !prefetchPlan.avatarSources.isEmpty else { return }
        let coverSourcesToPrefetch = prefetchPlan.coverSources
        let avatarSourcesToPrefetch = prefetchPlan.avatarSources
        let coverTargetPixelSize = prefetchPlan.coverTargetPixelSize
        let avatarTargetPixelSize = prefetchPlan.avatarTargetPixelSize
        imagePrefetchTask = Task(priority: .utility) {
            async let coverPrefetch: Void = RemoteImageCache.shared.prefetch(
                coverSourcesToPrefetch,
                targetPixelSize: coverTargetPixelSize,
                maximumConcurrentLoads: 1
            )
            async let avatarPrefetch: Void = RemoteImageCache.shared.prefetch(
                avatarSourcesToPrefetch,
                targetPixelSize: avatarTargetPixelSize,
                maximumConcurrentLoads: 1
            )
            _ = await (coverPrefetch, avatarPrefetch)
        }
    }
}
