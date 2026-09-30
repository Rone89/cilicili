import Foundation
import OSLog

extension VideoDetailViewModel {
    func loadPlayURL(mode: VideoDetailPlayURLLoadMode = .normal) async {
        #if DEBUG
        let startupTraceID = String(UUID().uuidString.prefix(8)).lowercased()
        #else
        let startupTraceID = ""
        #endif
        await loadPlayURL(mode: mode, startupTraceID: startupTraceID)
    }

    private func loadPlayURL(mode: VideoDetailPlayURLLoadMode, startupTraceID: String) async {
        guard !isPlaybackInvalidatedForNavigation else { return }
        let traceSuffix = startupTraceID.isEmpty ? "" : " traceID=\(startupTraceID)"
        let signpostState = PlayerMetricsLog.beginSignpostedInterval(
            "VideoDetailPlayURL",
            message: "bvid=\(detail.bvid) cid=\(selectedCID ?? 0) mode=\(mode)\(traceSuffix)"
        )
        var signpostMessage = "bvid=\(detail.bvid) loading\(traceSuffix)"
        defer {
            PlayerMetricsLog.endSignpostedInterval(
                "VideoDetailPlayURL",
                signpostState,
                message: signpostMessage
            )
        }
        preparePlayURLLoading(mode: mode, traceID: startupTraceID)
        guard let cid = selectedCID else {
            failPlayURLLoadingForMissingCID()
            signpostMessage = "bvid=\(detail.bvid) missing cid"
            return
        }
        let pageNumber = selectedPageNumber
        #if DEBUG
        let relatedPrefetchState = await VideoPreloadCenter.shared.relatedRowPlayURLPrefetchStateAtClick(
            bvid: detail.bvid,
            cid: cid,
            page: pageNumber,
            preferredQuality: adaptiveStartupPreferredQuality
        )
        PlayerMetricsLog.record(
            .startupScheduler,
            metricsID: detail.bvid,
            title: detail.title,
            message: "prefetchAtClick \(relatedPrefetchState)"
        )
        #endif
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
            if await prepareHistoryResumeBeforeApplyingPlayURL(data, cid: cid) {
                signpostMessage = "bvid=\(detail.bvid) history cid"
                await loadPlayURL(mode: mode, startupTraceID: startupTraceID)
                return
            }
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
