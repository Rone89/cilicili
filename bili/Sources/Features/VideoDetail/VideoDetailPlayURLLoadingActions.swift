import Foundation
import OSLog

extension VideoDetailViewModel {
    func loadPlayURL(mode: VideoDetailPlayURLLoadMode = .normal) async {
        #if DEBUG
        let relatedClickContext = PlayerMetricsLog.takeRelatedCandidateClickContext(
            bvid: detail.bvid,
            cid: selectedCID
        )
        let startupTraceID = relatedClickContext?.traceID ?? String(UUID().uuidString.prefix(8)).lowercased()
        #else
        let startupTraceID = ""
        let relatedClickContext: PlayerMetricsLog.RelatedCandidateClickContext? = nil
        #endif
        await loadPlayURL(
            mode: mode,
            startupTraceID: startupTraceID,
            relatedClickContext: relatedClickContext
        )
    }

    private func loadPlayURL(
        mode: VideoDetailPlayURLLoadMode,
        startupTraceID: String,
        relatedClickContext: PlayerMetricsLog.RelatedCandidateClickContext? = nil
    ) async {
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
        var relatedPrefetchState: String?
        if let relatedClickContext {
            relatedPrefetchState = await VideoPreloadCenter.shared.relatedRowPlayURLPrefetchStateAtClick(
                bvid: detail.bvid,
                cid: cid,
                page: pageNumber,
                preferredQuality: adaptiveStartupPreferredQuality,
                relatedTraceID: relatedClickContext.traceID,
                clickAt: relatedClickContext.clickedAt,
                stateBeforePreload: relatedClickContext.state,
                relatedPreloadSource: relatedClickContext.source
            )
            PlayerMetricsLog.record(
                .startupScheduler,
                metricsID: detail.bvid,
                title: detail.title,
                message: "relatedPrefetchAtClick \(relatedPrefetchState ?? "unknown") funnel=\(PlayerMetricsLog.relatedPrefetchFunnelSummary())"
            )
        }
        PlayerMetricsLog.recordStartupTraceEvent(
                metricsID: detail.bvid,
                event: "foregroundLookup",
                fields: [
                    "candidate": "\(detail.bvid):\(cid)",
                    "candidateTraceSource": relatedClickContext?.source ?? "other",
                    "candidateRequestedQuality": String(relatedClickContext?.requestedQuality ?? 0),
                    "candidateRequestedCodecPolicy": relatedClickContext?.requestedCodec ?? "unknown",
                    "prefetchStateAtClick": relatedPrefetchState.map {
                        Self.traceField("stateAtClick", in: $0) ?? "unknown"
                    } ?? "unknown",
            ]
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
                #if DEBUG
                let state = relatedPrefetchState
                    .flatMap { RelatedPrefetchClickState(rawValue: Self.traceField("stateAtClick", in: $0) ?? "") }
                    ?? .unknown
                let reason = relatedPrefetchState.flatMap { Self.traceField("missReason", in: $0) }
                let consumeResult = RelatedPrefetchDiagnostics.consumeResult(
                    cacheSource: nil,
                    stateAtClick: state,
                    missReason: reason
                ).rawValue
                PlayerMetricsLog.recordStartupTraceEvent(
                    metricsID: detail.bvid,
                    event: "foregroundMiss",
                    fields: [
                        "consumeResult": consumeResult,
                        "missReason": reason ?? "unknown",
                        "candidateTraceSource": relatedClickContext?.source ?? "other",
                    ]
                )
                #endif
            }
            let data = try await loadedNetworkPlayURLData(cid: cid, page: pageNumber)
            if await prepareHistoryResumeBeforeApplyingPlayURL(data, cid: cid) {
                signpostMessage = "bvid=\(detail.bvid) history cid"
                await loadPlayURL(
                    mode: mode,
                    startupTraceID: startupTraceID,
                    relatedClickContext: relatedClickContext
                )
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

    #if DEBUG
    private static func traceField(_ key: String, in summary: String) -> String? {
        summary.split(separator: " ").first { $0.hasPrefix("\(key)=") }
            .map { String($0.dropFirst(key.count + 1)) }
    }
    #endif

}
