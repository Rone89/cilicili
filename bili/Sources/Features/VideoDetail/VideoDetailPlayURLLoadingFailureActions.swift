import Foundation

extension VideoDetailViewModel {
    func handlePlayURLLoadingError(
        _ error: Error,
        cid: Int,
        page: Int?,
        mode: VideoDetailPlayURLLoadMode,
        deferredPlayableFallback: VideoDetailPlayURLFallback?
    ) async -> VideoDetailPlayURLFailureHandlingResult {
        guard !Task.isCancelled else {
            return .aborted(signpostMessage: "bvid=\(detail.bvid) cancelled")
        }
        guard !isPlaybackInvalidatedForNavigation else {
            return .aborted(signpostMessage: "bvid=\(detail.bvid) invalidated")
        }
        if let fallbackSignpostMessage = await applyPlayURLFailureFallbackIfNeeded(
            error,
            cid: cid,
            page: page,
            mode: mode,
            deferredPlayableFallback: deferredPlayableFallback
        ) {
            return .handled(signpostMessage: fallbackSignpostMessage)
        }
        handlePlayURLFailure(error)
        return .handled(signpostMessage: "bvid=\(detail.bvid) failed \(error.localizedDescription)")
    }
}
