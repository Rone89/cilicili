import XCTest
@testable import bili

final class PlaybackStartupTraceDiagnosticsTests: XCTestCase {
    @MainActor
    func testRelatedCandidateTraceKeepsIdentityFromStartupWarmupThroughClick() {
        let bvid = "gate7-\(UUID().uuidString)"
        let cid = Int.random(in: 1_000_000...9_999_999)
        let traceID = PlayerMetricsLog.ensureRelatedCandidateTrace(
            bvid: bvid,
            cid: cid,
            source: "relatedStartup",
            requestedQuality: 112,
            requestedCodec: "avc",
            visible: false
        )
        PlayerMetricsLog.updateRelatedCandidateTrace(
            traceID: traceID,
            event: "prefetchScheduled",
            state: "scheduled",
            fields: ["preloadSource": "relatedStartup"]
        )
        PlayerMetricsLog.updateRelatedCandidateTrace(
            traceID: traceID,
            event: "prefetchStarted",
            state: "running"
        )
        PlayerMetricsLog.updateRelatedCandidateTrace(
            traceID: traceID,
            event: "prefetchCompleted",
            state: "completed"
        )

        let visibleTraceID = PlayerMetricsLog.ensureRelatedCandidateTrace(
            bvid: bvid,
            cid: cid,
            source: "relatedRow",
            requestedQuality: 112,
            requestedCodec: "avc",
            visible: true
        )
        XCTAssertEqual(visibleTraceID, traceID)

        PlayerMetricsLog.markRelatedCandidateClicked(bvid: bvid, cid: cid)
        let context = PlayerMetricsLog.takeRelatedCandidateClickContext(bvid: bvid, cid: cid)
        XCTAssertEqual(context?.traceID, traceID)
        XCTAssertEqual(context?.state, "completed")
        XCTAssertEqual(context?.source, "relatedStartup")
        XCTAssertEqual(context?.requestedQuality, 112)
        XCTAssertEqual(context?.requestedCodec, "avc")

        PlayerMetricsLog.recordRelatedCandidateClickResolution(
            traceID: traceID,
            stateAtClick: "completed",
            consumeResult: "completedCacheHit",
            leadBucket: "500-1000ms",
            qualityMatch: true,
            codecPolicyMatch: true,
            preloadSource: "relatedStartup",
            at: CACurrentMediaTime()
        )
        XCTAssertNil(PlayerMetricsLog.takeRelatedCandidateClickContext(bvid: bvid, cid: cid))
    }

    @MainActor
    func testRelatedClickRetainsTraceWhenResolvedCIDDiffersFromCandidateCID() {
        let bvid = "gate7-cid-mismatch-\(UUID().uuidString)"
        let candidateCID = Int.random(in: 1_000_000...9_999_999)
        let traceID = PlayerMetricsLog.ensureRelatedCandidateTrace(
            bvid: bvid,
            cid: candidateCID,
            source: "relatedRow",
            requestedQuality: 80,
            requestedCodec: "avc",
            visible: true
        )
        PlayerMetricsLog.markRelatedCandidateClicked(bvid: bvid, cid: candidateCID)

        let context = PlayerMetricsLog.takeRelatedCandidateClickContext(
            bvid: bvid,
            cid: candidateCID + 1
        )
        XCTAssertEqual(context?.traceID, traceID)
        XCTAssertEqual(context?.cid, candidateCID)
        XCTAssertEqual(
            RelatedPrefetchDiagnostics.consumeResult(
                cacheSource: nil,
                stateAtClick: .completed,
                missReason: "prefetchMissDifferentIdentity"
            ),
            .missDifferentIdentity
        )
    }

    func testRelatedPrefetchStateAtClickUsesEventTimesRatherThanLookupTime() {
        XCTAssertEqual(
            RelatedPrefetchDiagnostics.stateAtClick(
                storedState: "completed", scheduledAt: 10, startedAt: 10.12, completedAt: 10.5,
                clickAt: 10.3
            ),
            .running
        )
        XCTAssertEqual(
            RelatedPrefetchDiagnostics.stateAtClick(
                storedState: "completed", scheduledAt: 10, startedAt: 10.12, completedAt: 10.5,
                clickAt: 10.6
            ),
            .completed
        )
        XCTAssertEqual(
            RelatedPrefetchDiagnostics.stateAtClick(
                storedState: "scheduled", scheduledAt: 10, startedAt: nil, completedAt: nil,
                clickAt: 10.05
            ),
            .scheduled
        )
        XCTAssertEqual(
            RelatedPrefetchDiagnostics.stateAtClick(
                storedState: "completed", scheduledAt: 10, startedAt: 10.1, completedAt: 10.2,
                clickAt: 10.7, cacheExpiresAt: 10.6
            ),
            .expired
        )
        XCTAssertEqual(
            RelatedPrefetchDiagnostics.stateAtClick(
                storedState: "completedUncached", scheduledAt: 10, startedAt: 10.1,
                completedAt: 10.2, clickAt: 10.7
            ),
            .completedUncached
        )
    }

    func testRelatedPrefetchLeadTimeBuckets() {
        XCTAssertEqual(RelatedPrefetchDiagnostics.leadMilliseconds(startedAt: 1, clickAt: 1.15)!, 150, accuracy: 0.001)
        XCTAssertEqual(RelatedPrefetchDiagnostics.leadBucket(for: 150), "lt200ms")
        XCTAssertEqual(RelatedPrefetchDiagnostics.leadBucket(for: 350), "200-500ms")
        XCTAssertEqual(RelatedPrefetchDiagnostics.leadBucket(for: 750), "500-1000ms")
        XCTAssertEqual(RelatedPrefetchDiagnostics.leadBucket(for: 1_500), "1-2s")
        XCTAssertEqual(RelatedPrefetchDiagnostics.leadBucket(for: 2_500), "gt2s")
        XCTAssertEqual(RelatedPrefetchDiagnostics.leadBucket(for: nil), "unknown")
    }

    func testRelatedPrefetchConsumeClassificationSeparatesPendingAndCache() {
        XCTAssertEqual(
            RelatedPrefetchDiagnostics.consumeResult(cacheSource: "pendingCache", stateAtClick: .running, missReason: nil),
            .pendingJoin
        )
        XCTAssertEqual(
            RelatedPrefetchDiagnostics.consumeResult(cacheSource: "playableCache", stateAtClick: .completed, missReason: nil),
            .completedCacheHit
        )
        XCTAssertEqual(
            RelatedPrefetchDiagnostics.consumeResult(cacheSource: nil, stateAtClick: .notScheduled, missReason: nil),
            .missNoPrefetch
        )
        XCTAssertEqual(
            RelatedPrefetchDiagnostics.consumeResult(cacheSource: nil, stateAtClick: .completed, missReason: "prefetchMissDifferentCodec"),
            .missDifferentCodec
        )
        XCTAssertEqual(
            RelatedPrefetchDiagnostics.consumeResult(cacheSource: nil, stateAtClick: .completed, missReason: "prefetchExpired"),
            .missExpired
        )
    }

    func testRelatedPrefetchScenariosProduceExpectedClickStateAndConsumeResult() {
        let completedState = RelatedPrefetchDiagnostics.stateAtClick(
            storedState: "completed", scheduledAt: 1, startedAt: 1.02, completedAt: 1.3, clickAt: 1.4
        )
        XCTAssertEqual(completedState, .completed)
        XCTAssertEqual(
            RelatedPrefetchDiagnostics.consumeResult(
                cacheSource: "completedCache", stateAtClick: completedState, missReason: nil
            ),
            .completedCacheHit
        )

        let pendingState = RelatedPrefetchDiagnostics.stateAtClick(
            storedState: "running", scheduledAt: 1, startedAt: 1.02, completedAt: nil, clickAt: 1.2
        )
        XCTAssertEqual(pendingState, .running)
        XCTAssertEqual(
            RelatedPrefetchDiagnostics.consumeResult(
                cacheSource: "pendingCache", stateAtClick: pendingState, missReason: nil
            ),
            .pendingJoin
        )

        let earlyClickState = RelatedPrefetchDiagnostics.stateAtClick(
            storedState: "scheduled", scheduledAt: 1.3, startedAt: nil, completedAt: nil, clickAt: 1.2
        )
        XCTAssertEqual(earlyClickState, .notScheduled)
        XCTAssertEqual(
            RelatedPrefetchDiagnostics.consumeResult(
                cacheSource: nil, stateAtClick: earlyClickState, missReason: "prefetchNotStarted"
            ),
            .missNoPrefetch
        )

        let failedState = RelatedPrefetchDiagnostics.stateAtClick(
            storedState: "failed", scheduledAt: 1, startedAt: 1.02, completedAt: 1.1, clickAt: 1.2
        )
        XCTAssertEqual(failedState, .failed)
        XCTAssertEqual(
            RelatedPrefetchDiagnostics.consumeResult(
                cacheSource: nil, stateAtClick: failedState, missReason: "prefetchDidNotProduceCache"
            ),
            .prefetchFailed
        )

        XCTAssertEqual(
            RelatedPrefetchDiagnostics.consumeResult(
                cacheSource: nil, stateAtClick: .completedUncached, missReason: "playURLNotReusable"
            ),
            .completedUncached
        )

        let expiredState = RelatedPrefetchDiagnostics.stateAtClick(
            storedState: "completed", scheduledAt: 1, startedAt: 1.02, completedAt: 1.1,
            clickAt: 2.2, cacheExpiresAt: 2
        )
        XCTAssertEqual(expiredState, .expired)
        XCTAssertEqual(
            RelatedPrefetchDiagnostics.consumeResult(
                cacheSource: nil, stateAtClick: expiredState, missReason: "prefetchExpired"
            ),
            .missExpired
        )
    }

    func testQualityCodecAndSanitizedHostClassification() {
        XCTAssertEqual(
            RelatedPrefetchDiagnostics.qualityCodecMatch(
                requestedQuality: 112, prefetchQuality: 64, requestedCodec: "avc", prefetchCodec: "hevc"
            ).quality,
            false
        )
        XCTAssertEqual(
            RelatedPrefetchDiagnostics.qualityCodecMatch(
                requestedQuality: 112, prefetchQuality: 112, requestedCodec: "avc", prefetchCodec: "avc"
            ).codec,
            true
        )
        XCTAssertEqual(
            RelatedPrefetchDiagnostics.qualityCodecMatch(
                requestedQuality: 112, prefetchQuality: 112, requestedCodec: "avc", prefetchCodec: "hevc"
            ).codec,
            false
        )
        XCTAssertEqual(RelatedPrefetchDiagnostics.cdnHostLabel("upos-sz-mirrorali.bilivideo.com"), "upos-sz-mirrorali")
        XCTAssertEqual(RelatedPrefetchDiagnostics.cdnHostLabel(nil), "unknown")
    }

    func testManifestStageEventsKeepTrackAndRangeMetricsSeparate() {
        let video = RelatedPrefetchDiagnostics.stageEvent(
            from: "videoIndexRangeFirstByte source=network bytes=128 ttfbMs=42.5"
        )
        let audio = RelatedPrefetchDiagnostics.stageEvent(
            from: "audioIndexRangeFirstByte source=memoryCache bytes=96 ttfbMs=-"
        )

        XCTAssertEqual(video.name, "videoIndexRangeFirstByte")
        XCTAssertEqual(video.fields["source"], "network")
        XCTAssertEqual(video.fields["bytes"], "128")
        XCTAssertEqual(video.fields["ttfbMs"], "42.5")
        XCTAssertEqual(audio.name, "audioIndexRangeFirstByte")
        XCTAssertEqual(audio.fields["source"], "memoryCache")
        XCTAssertEqual(audio.fields["bytes"], "96")
        XCTAssertEqual(audio.fields["ttfbMs"], "-")

        let unstructured = RelatedPrefetchDiagnostics.stageEvent(
            from: "renditions=7.2 video=q112-avc videoRefs=4 audioRefs=4"
        )
        XCTAssertEqual(unstructured.name, "renditions")
        XCTAssertEqual(unstructured.fields["value"], "7.2")
        XCTAssertEqual(unstructured.fields["video"], "q112-avc")
        XCTAssertEqual(unstructured.fields["videoRefs"], "4")
        XCTAssertEqual(unstructured.fields["audioRefs"], "4")
    }

    @MainActor
    func testManifestStageExportRetainsStartupRangeEventsAcrossFullTrace() {
        let metricsID = "gate7-trace-retention-\(UUID().uuidString)"
        let store = PlayerPerformanceStore.shared

        store.record(
            .manifestStage,
            metricsID: metricsID,
            message: "videoIndexRangeFirstByte source=network ttfbMs=42.5"
        )
        for index in 0..<26 {
            store.record(
                .manifestStage,
                metricsID: metricsID,
                message: "startupStage\(index)=complete"
            )
        }
        store.record(
            .manifestStage,
            metricsID: metricsID,
            message: "videoMediaFirstByte source=network ttfbMs=88.0"
        )
        store.record(
            .manifestStage,
            metricsID: metricsID,
            message: "audioMediaFirstByte source=memoryCache ttfbMs=-"
        )

        let exported = PlayerPerformanceCopyTextFormatter.performanceCopyText(
            metricsID: metricsID,
            session: store.session(for: metricsID)
        )
        XCTAssertTrue(exported.contains("videoIndexRangeFirstByte source=network ttfbMs=42.5"))
        XCTAssertTrue(exported.contains("videoMediaFirstByte source=network ttfbMs=88.0"))
        XCTAssertTrue(exported.contains("audioMediaFirstByte source=memoryCache ttfbMs=-"))
    }
}
