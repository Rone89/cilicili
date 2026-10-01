import SwiftUI

@MainActor
struct VideoDetailRelatedPreloadActions {
    @Binding var preloadedVideoIDs: Set<String>
    let api: BiliAPIClient
    let runtimeSettings: VideoDetailRuntimeSettingsSnapshot

    func beginPreloadIfNeeded(_ video: VideoItem) async {
        #if DEBUG
        let codecPolicy = VideoCodecPreference.stored().rawValue
        let traceID: String
        if let cid = video.cid {
            traceID = PlayerMetricsLog.ensureRelatedCandidateTrace(
                bvid: video.bvid,
                cid: cid,
                source: "relatedRow",
                requestedQuality: runtimeSettings.preferredVideoQuality,
                requestedCodec: codecPolicy,
                visible: true
            )
        } else {
            traceID = String(UUID().uuidString.prefix(8)).lowercased()
        }
        #else
        let traceID = ""
        #endif
        let preferredQuality = runtimeSettings.preferredVideoQuality
        func log(_ state: String, reason: String? = nil) {
            #if DEBUG
            let event = switch state {
            case "scheduled": "prefetchScheduled"
            case "started", "startedWebpageOnly": "prefetchStarted"
            case "completed": "prefetchCompleted"
            case "failed": "prefetchFailed"
            case "cancelled": "prefetchCancelled"
            default: "prefetchNotScheduled"
            }
            if video.cid != nil {
                PlayerMetricsLog.updateRelatedCandidateTrace(
                    traceID: traceID,
                    event: event,
                    state: event == "prefetchNotScheduled" ? "notScheduled" : state,
                    fields: [
                        "q": String(preferredQuality ?? 0),
                        "codec": codecPolicy,
                        "preloadSource": "relatedRow",
                        "reason": reason ?? "-",
                    ]
                )
            } else {
                PlayerMetricsLog.diagnostic(
                    "[StartupTrace] traceID=\(traceID) candidate=\(video.bvid):0 source=relatedRow event=\(event) reason=\(reason ?? "-")"
                )
            }
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

        #if DEBUG
        if video.cid != nil {
            PlayerMetricsLog.markRelatedCandidateSelected(
                traceID: traceID,
                fields: [
                    "q": String(preferredQuality ?? 0),
                    "codec": codecPolicy,
                    "selection": "relatedPreloadBudget",
                ]
            )
        }
        #endif
        log("scheduled", reason: "delayMs=120")
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
        if video.cid == nil {
            log("startedWebpageOnly")
        }
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
            relatedPrefetchID: relatedPrefetchID,
            preloadSource: "relatedRow"
        )
    }
}
