import Foundation
import OSLog

extension VideoDetailViewModel {
    func loadPlayURL(mode: VideoDetailPlayURLLoadMode = .normal) async {
        guard !isPlaybackInvalidatedForNavigation else { return }
        let signpostState = PlayerMetricsLog.beginSignpostedInterval(
            "VideoDetailPlayURL",
            message: "bvid=\(detail.bvid) cid=\(selectedCID ?? 0) mode=\(mode)"
        )
        var signpostMessage = "bvid=\(detail.bvid) loading"
        defer {
            PlayerMetricsLog.endSignpostedInterval(
                "VideoDetailPlayURL",
                signpostState,
                message: signpostMessage
            )
        }
        preparePlayURLLoading(mode: mode)
        guard let cid = selectedCID else {
            failPlayURLLoadingForMissingCID()
            signpostMessage = "bvid=\(detail.bvid) missing cid"
            return
        }
        let pageNumber = selectedPageNumber
        var deferredPlayableFallback: VideoDetailPlayURLFallback?

        do {
            prepareNetworkPreferencesForPlayURLLoading()
            switch await resolveCachedPlayURLForStartup(cid: cid, page: pageNumber, mode: mode) {
            case .loaded(let message):
                signpostMessage = message
                return
            case .needsNetwork(let fallback):
                deferredPlayableFallback = fallback
            }
            let data = try await loadedNetworkPlayURLData(cid: cid, page: pageNumber)
            switch await applyNetworkPlayURLData(data, cid: cid, page: pageNumber) {
            case .applied(let message), .aborted(let message):
                signpostMessage = message
            }
        } catch {
            switch await handlePlayURLLoadingError(
                error,
                cid: cid,
                page: pageNumber,
                mode: mode,
                deferredPlayableFallback: deferredPlayableFallback
            ) {
            case .handled(let message), .aborted(let message):
                signpostMessage = message
            }
        }
    }

}
