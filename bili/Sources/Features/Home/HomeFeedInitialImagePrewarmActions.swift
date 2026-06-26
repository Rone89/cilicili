import Foundation

extension HomeFeedMediaPreloadCoordinator {
    func prewarmInitialImagesBeforePublishing(_ videos: [VideoItem]) async {
        let prefetchPlan = HomeFeedImagePrefetchPlan.make(
            for: videos,
            layout: libraryStore.homeFeedLayout,
            limit: 3
        )
        guard !prefetchPlan.coverSources.isEmpty || !prefetchPlan.avatarSources.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                async let coverPrefetch: Void = RemoteImageCache.shared.prefetch(
                    prefetchPlan.coverSources,
                    targetPixelSize: prefetchPlan.coverTargetPixelSize,
                    maximumConcurrentLoads: 1
                )
                async let avatarPrefetch: Void = RemoteImageCache.shared.prefetch(
                    prefetchPlan.avatarSources,
                    targetPixelSize: prefetchPlan.avatarTargetPixelSize,
                    maximumConcurrentLoads: 1
                )
                _ = await (coverPrefetch, avatarPrefetch)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 320_000_000)
            }
            _ = await group.next()
            group.cancelAll()
        }
    }
}
