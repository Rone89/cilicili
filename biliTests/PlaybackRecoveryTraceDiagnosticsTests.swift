import Foundation
import XCTest
@testable import bili

final class PlaybackRecoveryTraceDiagnosticsTests: XCTestCase {
    func testBufferCoverageUsesContainingRange() {
        let ranges = [
            RecoveryTraceDiagnostics.LoadedRange(start: 0, duration: 10),
            RecoveryTraceDiagnostics.LoadedRange(start: 100, duration: 1_000),
            RecoveryTraceDiagnostics.LoadedRange(start: .infinity, duration: 1),
            RecoveryTraceDiagnostics.LoadedRange(start: 20, duration: 0),
        ]

        let covered = RecoveryTraceDiagnostics.bufferCoverage(currentTime: 5, ranges: ranges)
        XCTAssertTrue(covered.covered)
        XCTAssertEqual(covered.ahead, 5, accuracy: 0.000_1)

        let gap = RecoveryTraceDiagnostics.bufferCoverage(currentTime: 50, ranges: ranges)
        XCTAssertFalse(gap.covered)
        XCTAssertEqual(gap.ahead, 0, accuracy: 0.000_1)

        XCTAssertFalse(RecoveryTraceDiagnostics.bufferCoverage(currentTime: -1, ranges: ranges).covered)
        XCTAssertFalse(RecoveryTraceDiagnostics.bufferCoverage(currentTime: 1_200, ranges: ranges).covered)
        XCTAssertFalse(RecoveryTraceDiagnostics.bufferCoverage(currentTime: 20, ranges: [.init(start: 20, duration: 0)]).covered)
        let invalidTime = RecoveryTraceDiagnostics.bufferCoverage(currentTime: .nan, ranges: ranges)
        XCTAssertFalse(invalidTime.covered)
        XCTAssertEqual(invalidTime.ahead, 0, accuracy: 0.000_1)
    }

    func testCancellationClassificationUsesActualError() {
        XCTAssertEqual(RecoveryTraceDiagnostics.rangeFailureEvent(CancellationError()), "rangeCancelled")
        XCTAssertEqual(RecoveryTraceDiagnostics.rangeFailureEvent(URLError(.cancelled)), "rangeCancelled")
        XCTAssertEqual(RecoveryTraceDiagnostics.rangeFailureEvent(URLError(.timedOut)), "rangeFailed")
    }

    func testRangeClassificationAndIdentity() {
        XCTAssertEqual(RecoveryTraceDiagnostics.rangeSource("cache"), "cache")
        XCTAssertEqual(RecoveryTraceDiagnostics.rangeSource("memoryCache"), "cache")
        XCTAssertEqual(RecoveryTraceDiagnostics.rangeSource("streamJoin"), "joined")
        XCTAssertEqual(RecoveryTraceDiagnostics.rangeSource("fetch"), "network")
        XCTAssertEqual(RecoveryTraceDiagnostics.rangeSource("somethingElse"), "unknown")
        XCTAssertEqual(RecoveryTraceDiagnostics.rangeSource(nil), "unknown")

        XCTAssertEqual(
            RecoveryTraceDiagnostics.sameRange(
                warmResource: "init-video",
                warmStart: 0,
                warmLength: 512,
                playerResource: "init-video",
                playerStart: 0,
                playerLength: 512
            ),
            true
        )
        XCTAssertEqual(
            RecoveryTraceDiagnostics.sameRange(
                warmResource: "init-video",
                warmStart: 0,
                warmLength: 512,
                playerResource: "init-video",
                playerStart: 512,
                playerLength: 512
            ),
            false
        )
        XCTAssertNil(
            RecoveryTraceDiagnostics.sameRange(
                warmResource: nil,
                warmStart: 0,
                warmLength: 512,
                playerResource: "init-video",
                playerStart: 0,
                playerLength: 512
            )
        )
    }

    func testRecoveryFrameEligibility() {
        XCTAssertFalse(
            RecoveryTraceDiagnostics.isRecoveryFrame(
                type: "manualResume", frameTime: 10.0005, baseline: 10,
                target: nil, seekCompleted: false, playCalled: true
            )
        )
        XCTAssertTrue(
            RecoveryTraceDiagnostics.isRecoveryFrame(
                type: "manualResume", frameTime: 10.002, baseline: 10,
                target: nil, seekCompleted: false, playCalled: true
            )
        )
        XCTAssertFalse(
            RecoveryTraceDiagnostics.isRecoveryFrame(
                type: "manualResume", frameTime: 10.002, baseline: 10,
                target: nil, seekCompleted: false, playCalled: false
            )
        )
        XCTAssertTrue(
            RecoveryTraceDiagnostics.isRecoveryFrame(
                type: "userSeek", frameTime: 20.7, baseline: 20,
                target: 20, seekCompleted: true, playCalled: false
            )
        )
        XCTAssertFalse(
            RecoveryTraceDiagnostics.isRecoveryFrame(
                type: "userSeek", frameTime: 20.76, baseline: 20,
                target: 20, seekCompleted: true, playCalled: false
            )
        )
        XCTAssertFalse(
            RecoveryTraceDiagnostics.isRecoveryFrame(
                type: "userSeek", frameTime: .infinity, baseline: 20,
                target: 20, seekCompleted: true, playCalled: false
            )
        )
    }

    func testManualResumeSummaryCalculatesPauseAudioAndFrameTransitions() {
        var record = RecoveryTraceRecord(
            id: "trace-manual",
            type: "manualResume",
            metricsID: "metrics-1",
            startedAt: 10,
            fields: ["opaque": "value"]
        )
        record.record(
            name: "resumeRequested",
            at: 10,
            fields: [
                "pauseStartedAt": "8",
                "currentTime": "42",
                "bufferAheadAtResume": "3.5",
                "bufferCoveredAtResume": "true",
            ]
        )
        record.record(name: "audioSessionActivationStart", at: 10.1, fields: ["phase": "play"])
        record.record(name: "audioSessionActivationComplete", at: 10.3, fields: ["phase": "play", "succeeded": "true"])
        record.record(name: "audioSessionActivationStart", at: 10.4, fields: ["phase": "recoverSurface"])
        record.record(name: "audioSessionActivationComplete", at: 10.7, fields: ["phase": "recoverSurface", "succeeded": "true"])
        record.record(name: "playCalled", at: 10.6)
        record.record(name: "playing", at: 10.8, fields: ["reason": "resume"])
        record.record(name: "firstNewFrame", at: 11.2)
        record.record(name: "waiting", at: 11.3, fields: ["reason": "toMinimizeStall"])

        let summary = record.summary
        XCTAssertTrue(summary.hasPrefix("[RecoveryTraceSummary] type=manualResume"))
        XCTAssertTrue(summary.contains("fields=opaque=value"))
        XCTAssertTrue(summary.contains("pauseDuration=2000.0ms"))
        XCTAssertTrue(summary.contains("audioActivationPlay=200.0ms"))
        XCTAssertTrue(summary.contains("audioActivationRecoverSurface=300.0ms"))
        XCTAssertTrue(summary.contains("audioConfig1=200.0ms"))
        XCTAssertTrue(summary.contains("audioConfig2=300.0ms"))
        XCTAssertTrue(summary.contains("resumeToPlayCalled=600.0ms"))
        XCTAssertTrue(summary.contains("playCalledToPlaying=200.0ms"))
        XCTAssertTrue(summary.contains("resumeToFirstFrame=1200.0ms"))
        XCTAssertTrue(summary.contains("waitingReason=toMinimizeStall"))
        XCTAssertTrue(summary.contains("resumeRequested@10.000"))
        XCTAssertTrue(summary.contains("firstNewFrame@11.200"))
        XCTAssertTrue(summary.contains("seekCallToCompletion=-"))
    }

    func testUserSeekSummaryUsesTargetFrameUIAndPlayerRangeFirstByte() {
        var record = RecoveryTraceRecord(
            id: "trace-seek",
            type: "userSeek",
            metricsID: nil,
            startedAt: 20,
            fields: ["oldRangeStillActive": "false"]
        )
        record.record(
            name: "seekRequested",
            at: 20,
            fields: ["rawTarget": "50", "wasPlayingBeforeSeek": "false"]
        )
        record.record(name: "seekAligned", at: 20.05, fields: ["alignedTarget": "49.8", "toleranceBefore": "0.35", "toleranceAfter": "0.35"])
        record.record(name: "recoverSurfaceStart", at: 20.41)
        record.record(name: "recoverSurfaceComplete", at: 20.45)
        record.record(name: "seekCall", at: 20.1)
        record.record(name: "seekCompletion", at: 20.4, fields: ["finished": "true"])
        record.record(name: "firstTargetFrame", at: 20.7)
        record.record(name: "uiReveal", at: 21.0, fields: ["reason": "targetFrame"])
        record.record(
            name: "rangeRequested",
            at: 20.2,
            fields: [
                "requestID": "warm-1", "origin": "warm", "track": "video",
                "resource": "init-video", "start": "0", "length": "512", "target": "true",
            ]
        )
        record.record(
            name: "rangeComplete",
            at: 20.3,
            fields: [
                "requestID": "warm-1", "origin": "warm", "track": "video",
                "resource": "init-video", "start": "0", "length": "512", "source": "memoryCache", "target": "true",
            ]
        )
        record.record(
            name: "rangeRequested",
            at: 20.5,
            fields: [
                "requestID": "player-1", "origin": "player", "track": "video",
                "resource": "init-video", "start": "0", "length": "512", "target": "true",
            ]
        )
        record.record(
            name: "rangeFirstByte",
            at: 20.62,
            fields: [
                "requestID": "player-1", "origin": "player", "track": "video",
                "resource": "init-video", "start": "0", "length": "512", "source": "network",
                "ttfbMs": "120",
            ]
        )
        record.record(
            name: "rangeComplete",
            at: 21.5,
            fields: [
                "requestID": "player-1", "origin": "player", "track": "video",
                "resource": "init-video", "start": "0", "length": "512", "source": "network",
            ]
        )

        let summary = record.summary
        XCTAssertTrue(summary.contains("rawTarget=50"))
        XCTAssertTrue(summary.contains("alignedTarget=49.8"))
        XCTAssertTrue(summary.contains("recoverSurfaceMs=40.0ms"))
        XCTAssertTrue(summary.contains("seekCallToCompletion=300.0ms"))
        XCTAssertTrue(summary.contains("seekRequestedToFirstTargetFrame=700.0ms"))
        XCTAssertTrue(summary.contains("firstTargetFrameToUIReveal=300.0ms"))
        XCTAssertTrue(summary.contains("seekRequestedToUIReveal=1000.0ms"))
        XCTAssertTrue(summary.contains("targetVideoRangeSource=network"))
        XCTAssertTrue(summary.contains("targetVideoRangeTTFB=120.0ms"))
        XCTAssertTrue(summary.contains("seekWarmSource=cache"))
        XCTAssertTrue(summary.contains("warmAndPlayerSameRange=true"))
        XCTAssertTrue(summary.contains("oldRangeStillActive=false"))
        XCTAssertFalse(summary.contains("targetVideoRangeTTFB=1000.0ms"))
        XCTAssertFalse(summary.contains("resource=init-video"))
    }

    func testTargetRangeFallbackAndCacheAvailabilityDoNotFabricateTTFB() {
        var record = RecoveryTraceRecord(
            id: "trace-range-fallback",
            type: "userSeek",
            metricsID: nil,
            startedAt: 1
        )
        record.record(
            name: "rangeRequested",
            at: 1.1,
            fields: ["requestID": "audio-1", "origin": "player", "track": "audio", "target": "true"]
        )
        record.record(
            name: "rangeComplete",
            at: 2.0,
            fields: ["requestID": "audio-1", "origin": "player", "track": "audio", "source": "streamJoin"]
        )
        record.record(
            name: "rangeRequested",
            at: 1.2,
            fields: ["requestID": "video-1", "origin": "player", "track": "video", "target": "true"]
        )
        record.record(
            name: "rangeFirstByte",
            at: 1.3,
            fields: ["requestID": "video-1", "origin": "player", "track": "video", "source": "memoryCache"]
        )
        record.record(
            name: "rangeComplete",
            at: 2.3,
            fields: ["requestID": "video-1", "origin": "player", "track": "video", "source": "network"]
        )

        let summary = record.summary
        XCTAssertTrue(summary.contains("targetAudioRangeSource=joined"))
        XCTAssertTrue(summary.contains("targetAudioRangeTTFB=-"))
        XCTAssertTrue(summary.contains("targetVideoRangeSource=cache"))
        XCTAssertTrue(summary.contains("targetVideoRangeTTFB=-"))
    }

    func testFirstTargetRequestDoesNotBorrowLaterRequestFirstByte() {
        var record = RecoveryTraceRecord(id: "r", type: "userSeek", metricsID: nil, startedAt: 1)
        let fields = ["origin": "player", "track": "video", "target": "true"]
        record.record(name: "rangeRequested", at: 1.1, fields: fields.merging(["requestID": "first"]) { _, new in new })
        record.record(name: "rangeRequested", at: 1.2, fields: fields.merging(["requestID": "later"]) { _, new in new })
        record.record(name: "rangeFirstByte", at: 1.3, fields: fields.merging(["requestID": "later", "source": "network"]) { _, new in new })
        record.record(name: "rangeComplete", at: 2, fields: fields.merging(["requestID": "first", "source": "joined"]) { _, new in new })
        XCTAssertTrue(record.summary.contains("targetVideoRangeSource=joined"))
        XCTAssertTrue(record.summary.contains("targetVideoRangeTTFB=-"))
    }

    func testOutOfOrderCallbacksAndBoundedEventsPreserveAnchor() {
        var record = RecoveryTraceRecord(id: "r", type: "manualResume", metricsID: nil, startedAt: 1)
        record.record(name: "resumeRequested", at: 1)
        record.record(name: "firstNewFrame", at: 3)
        record.record(name: "playCalled", at: 2)
        XCTAssertTrue(record.summary.contains("playCalledToFirstFrame=1000.0ms"))
        for index in 0..<200 {
            record.record(name: "waiting", at: 4 + Double(index), fields: ["reason": String(index)])
        }
        XCTAssertEqual(record.events.count, 160)
        XCTAssertEqual(record.events.first?.name, "resumeRequested")
        XCTAssertTrue(record.exportText.contains("at=1.000 event=resumeRequested"))
    }

    func testRevealDecisionSummaryDistinguishesTimeoutFromReadiness() {
        var record = RecoveryTraceRecord(id: "reveal", type: "userSeek", metricsID: nil, startedAt: 1)
        XCTAssertTrue(record.summary.contains("uiRevealLastReason=-"))
        XCTAssertTrue(record.summary.contains("uiRevealTimeoutFallback=-"))
        record.record(name: "uiRevealDecision", at: 2, fields: ["decision": "blocked", "reason": "surfaceBlack", "resetCount": "2"])
        XCTAssertTrue(record.summary.contains("uiRevealLastReason=surfaceBlack"))
        XCTAssertTrue(record.summary.contains("uiRevealTimeoutFallback=false"))
        record.record(name: "uiRevealDecision", at: 4, fields: ["decision": "timeoutFallback", "reason": "maximumWait", "resetCount": "2"])
        XCTAssertTrue(record.summary.contains("uiRevealResetCount=2"))
        XCTAssertTrue(record.summary.contains("uiRevealTimeoutFallback=true"))
    }

    func testMissingSummaryValuesRemainUnknown() {
        let record = RecoveryTraceRecord(
            id: "trace-incomplete",
            type: "manualResume",
            metricsID: nil,
            startedAt: 1
        )
        let summary = record.summary
        XCTAssertTrue(summary.contains("pauseDuration=-"))
        XCTAssertTrue(summary.contains("recoverSurfaceMs=-"))
        XCTAssertTrue(summary.contains("targetVideoRangeSource=-"))
        XCTAssertTrue(summary.contains("waitingReason=-"))
        XCTAssertFalse(summary.contains("pauseDuration=0.0ms"))
    }

#if DEBUG
    func testDebugStoreAddsInitialEventBoundsRecordsAndExportsTimes() {
        let store = RecoveryTraceStore()
        let firstID = store.start(type: "manualResume", metricsID: "m", at: 1)
        store.event(firstID, "firstNewFrame", at: 2)
        XCTAssertTrue(store.summary(firstID)?.contains("resumeRequested@1.000") == true)
        let export = store.exportText()
        XCTAssertTrue(export.contains("at=1.000 event=resumeRequested fields=-"))
        XCTAssertTrue(export.contains("at=2.000 event=firstNewFrame fields=-"))

        for index in 0..<81 {
            _ = store.start(type: "userSeek", metricsID: "m", at: Double(index + 3))
        }
        XCTAssertNil(store.summary(firstID))

        let boundedID = store.start(type: "manualResume", metricsID: "m", at: 100)
        for index in 0..<200 {
            store.event(boundedID, "waiting", at: 101 + Double(index), fields: ["reason": "buffer"])
        }
        let eventCount = store.summary(boundedID)?.components(separatedBy: "@").count ?? 0
        XCTAssertLessThanOrEqual(eventCount, 161)
    }
#endif
}
