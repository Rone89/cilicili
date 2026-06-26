import Foundation

extension VideoDetailViewModel {
    func resolveStartupCachedPlayURLCandidate(
        _ data: PlayURLData,
        cid: Int,
        page: Int?,
        mode: VideoDetailPlayURLLoadMode,
        cacheKind: String,
        fallbackSource: String,
        loadedSource: String,
        targetMissSource: String,
        loadedSignpost: String,
        deferredFallback: inout VideoDetailPlayURLFallback?
    ) async -> VideoDetailPlayURLCacheResolution? {
        guard !isPlaybackInvalidatedForNavigation else {
            return .loaded(signpostMessage: "bvid=\(detail.bvid) invalidated")
        }

        if shouldRefetchForStartupQuality(data) {
            rememberDeferredPlayableFallback(
                data,
                source: fallbackSource,
                mode: mode,
                deferredFallback: &deferredFallback
            )
            logPlayURLCacheBypass(kind: cacheKind, data: data)
            return nil
        }

        if shouldRefetchForPreferredQuality(data),
           libraryStore.preferredVideoQuality != nil {
            rememberDeferredPlayableFallback(
                data,
                source: fallbackSource,
                mode: mode,
                deferredFallback: &deferredFallback
            )
            logPlayURLCacheBypass(kind: "\(cacheKind)TargetMiss", data: data)
            return nil
        }

        let source = shouldRefetchForPreferredQuality(data) ? targetMissSource : loadedSource
        await applyCachedPlayURLData(
            data,
            cid: cid,
            page: page,
            source: source
        )
        return .loaded(signpostMessage: loadedSignpost)
    }
}
