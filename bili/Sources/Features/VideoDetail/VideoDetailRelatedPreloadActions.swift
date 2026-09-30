import SwiftUI

@MainActor
struct VideoDetailRelatedPreloadActions {
    @Binding var preloadedVideoIDs: Set<String>
    let api: BiliAPIClient
    let runtimeSettings: VideoDetailRuntimeSettingsSnapshot

    func beginPreloadIfNeeded(_ video: VideoItem) async {
        #if DEBUG
        let traceID = String(UUID().uuidString.prefix(8)).lowercased()
        #else
        let traceID = ""
        #endif
        let preferredQuality = runtimeSettings.preferredVideoQuality
        #if DEBUG
        let codecPolicy = VideoCodecPreference.stored().rawValue
        #endif
        func log(_ state: String, reason: String? = nil) {
            #if DEBUG
            PlayerMetricsLog.diagnostic(
                [
                    "event=relatedPlayURLPrefetch",
                    "traceID=\(traceID)",
                    "metricsID=\(video.bvid)",
                    "cid=\(video.cid ?? 0)",
                    "state=\(state)",
                    "q=\(preferredQuality ?? 0)",
                    "codecPolicy=\(codecPolicy)",
                    reason.map { "reason=\($0)" },
                ].compactMap { $0 }.joined(separator: " ")
            )
            #endif
        }

        guard !video.bvid.isEmpty else {
            log("skipped", reason: "missingBVID")
            return
        }
        guard !preloadedVideoIDs.contains(video.bvid) else {
            log("skipped", reason: "alreadySelected")
            return
        }
        guard preloadedVideoIDs.count < 1 else {
            log("skipped", reason: "oneTargetLimit")
            return
        }
        guard !PlaybackEnvironment.current.shouldPreferConservativePlayback else {
            log("skipped", reason: "conservativeNetwork")
            return
        }

        let playbackAdaptationProfile = PlayerPerformanceStore.shared.playbackAdaptationProfile(
            isEnabled: runtimeSettings.playbackAutoOptimizationEnabled
        )
        guard playbackAdaptationProfile.backgroundPreloadLimit > 1 else {
            log("skipped", reason: "adaptationBudget")
            return
        }

        preloadedVideoIDs.insert(video.bvid)
        do {
            try await Task.sleep(nanoseconds: 120_000_000)
        } catch {
            preloadedVideoIDs.remove(video.bvid)
            log("cancelled", reason: "visibilityDelayCancelled")
            return
        }
        guard !Task.isCancelled else {
            preloadedVideoIDs.remove(video.bvid)
            log("cancelled", reason: "taskCancelled")
            return
        }
        log(video.cid == nil ? "startedWebpageOnly" : "started")
        #if DEBUG
        let relatedPrefetchID: String? = traceID
        #else
        let relatedPrefetchID: String? = nil
        #endif
        await VideoPreloadCenter.shared.preloadPlayInfo(
            video,
            api: api,
            preferredQuality: preferredQuality,
            cdnPreference: runtimeSettings.effectivePlaybackCDNPreference,
            priority: .utility,
            warmsMedia: false,
            mediaWarmupMode: .routePlanOnly,
            mediaWarmupDelay: 0,
            playbackAdaptationProfile: playbackAdaptationProfile,
            relatedPrefetchID: relatedPrefetchID
        )
    }
}
