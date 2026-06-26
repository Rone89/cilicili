import Foundation

extension VideoDetailViewModel {
    func applyPlayURLFailureFallbackIfNeeded(
        _ error: Error,
        cid: Int,
        page: Int?,
        mode: VideoDetailPlayURLLoadMode,
        deferredPlayableFallback: VideoDetailPlayURLFallback?
    ) async -> String? {
        if mode.allowsNetworkFailureCacheFallback {
            if let signpostMessage = await applyDeferredPlayURLFallbackIfAvailable(
                deferredPlayableFallback,
                error: error,
                cid: cid,
                page: page
            ) {
                return signpostMessage
            }
            if let signpostMessage = await applyStalePlayablePlayURLFallbackIfAvailable(
                error: error,
                cid: cid,
                page: page
            ) {
                return signpostMessage
            }
            if let signpostMessage = await applyMemoryPlayablePlayURLFallbackIfAvailable(
                error: error,
                cid: cid,
                page: page
            ) {
                return signpostMessage
            }
        }
        if await recoverPlayURLAfterFailure(error, cid: cid, page: page) {
            return "bvid=\(detail.bvid) recovered after failure"
        }
        return nil
    }

    func handlePlayURLFailure(_ error: Error) {
        playVariants = []
        selectedPlayVariant = nil
        isSupplementingPlayQualities = false
        playURLElapsedMilliseconds = elapsedMilliseconds(since: playURLLoadStartTime)
        playURLState = .failed(error.localizedDescription)
    }
}
