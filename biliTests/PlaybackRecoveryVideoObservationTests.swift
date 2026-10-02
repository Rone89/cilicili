import XCTest
@testable import bili

final class PlaybackRecoveryVideoObservationTests: XCTestCase {
    func testStaticTimestampDoesNotBecomeAdvancement() {
        var observation = RecoveryVideoObservation()
        XCTAssertEqual(observation.observe(frameTime: 50, qualifies: true, origin: .snapshot, at: 1), "targetVideoAvailable")
        XCTAssertNil(observation.observe(frameTime: 50, qualifies: true, origin: .debugPoll, at: 1.1))
        XCTAssertNil(observation.observe(frameTime: 50, qualifies: true, origin: .snapshot, at: 1.2))
        XCTAssertNil(observation.observe(frameTime: nil, qualifies: false, origin: .snapshot, at: 1.3))
        XCTAssertNil(observation.firstAdvancing)
        XCTAssertEqual(observation.fields["snapshotRepeated"], "1")
        XCTAssertEqual(observation.fields["snapshotMissing"], "1")
        XCTAssertEqual(observation.fields["advancingAt"], "-")
    }

    func testExistingReadersCanContributeIndependentEvidenceOnce() {
        var observation = RecoveryVideoObservation()
        XCTAssertEqual(observation.observe(frameTime: 50, qualifies: true, origin: .snapshot, at: 1), "targetVideoAvailable")
        XCTAssertEqual(observation.observe(frameTime: 50.04, qualifies: true, origin: .debugPoll, at: 1.2), "targetVideoAdvanceObserved")
        XCTAssertNil(observation.observe(frameTime: 50.08, qualifies: true, origin: .frameImage, at: 1.3))
        XCTAssertEqual(observation.firstAvailable?.origin, .snapshot)
        XCTAssertEqual(observation.firstAdvancing?.origin, .debugPoll)
        XCTAssertEqual(observation.firstAdvancing?.at, 1.2)
    }

    func testOutOfTargetAndInvalidSamplesCannotSupplyMotion() {
        var observation = RecoveryVideoObservation()
        XCTAssertNil(observation.observe(frameTime: 4, qualifies: false, origin: .debugPoll, at: 1))
        XCTAssertNil(observation.observe(frameTime: .nan, qualifies: true, origin: .debugPoll, at: 1.1))
        XCTAssertNil(observation.observe(frameTime: -1, qualifies: true, origin: .debugPoll, at: 1.2))
        XCTAssertNil(observation.firstAvailable)
        XCTAssertEqual(observation.fields["debugPollRejected"], "3")
        XCTAssertEqual(observation.observe(frameTime: 50, qualifies: true, origin: .snapshot, at: 1.3), "targetVideoAvailable")
        XCTAssertNil(observation.firstAdvancing)
    }

    func testRegressionReseedsComparisonAndNewTraceStartsEmpty() {
        var observation = RecoveryVideoObservation()
        _ = observation.observe(frameTime: 50, qualifies: true, origin: .snapshot, at: 1)
        XCTAssertNil(observation.observe(frameTime: 49.9, qualifies: true, origin: .snapshot, at: 1.1))
        XCTAssertNil(observation.firstAdvancing)
        XCTAssertEqual(observation.observe(frameTime: 49.94, qualifies: true, origin: .snapshot, at: 1.2), "targetVideoAdvanceObserved")
        observation = RecoveryVideoObservation()
        XCTAssertNil(observation.firstAvailable)
        XCTAssertNil(observation.firstAdvancing)
        XCTAssertEqual(observation.fields["snapshotReads"], "-")
    }

    func testReaderGapsAreSeparateAndNonMonotonicCallsAreRejected() {
        var observation = RecoveryVideoObservation()
        _ = observation.observe(frameTime: 50, qualifies: true, origin: .snapshot, at: 1)
        _ = observation.observe(frameTime: nil, qualifies: false, origin: .debugPoll, at: 1.01)
        _ = observation.observe(frameTime: nil, qualifies: false, origin: .debugPoll, at: 1.02)
        _ = observation.observe(frameTime: 50.04, qualifies: true, origin: .snapshot, at: 1.3)
        XCTAssertEqual(Double(observation.fields["snapshotMaxGapMs"]!)!, 300, accuracy: 0.001)
        XCTAssertEqual(Double(observation.fields["debugPollMaxGapMs"]!)!, 10, accuracy: 0.001)
        XCTAssertNil(observation.observe(frameTime: 51, qualifies: true, origin: .snapshot, at: 1.2))
        XCTAssertNil(observation.observe(frameTime: 51, qualifies: true, origin: .snapshot, at: .infinity))
        XCTAssertEqual(observation.fields["snapshotReads"], "2")
        XCTAssertEqual(observation.firstAdvancing?.mediaTime, 50.04)
    }

    func testSummarySeparatesVideoEvidenceFromUIConfirmationAndSettle() {
        var observation = RecoveryVideoObservation()
        _ = observation.observe(frameTime: 50, qualifies: true, origin: .snapshot, at: 1.2)
        _ = observation.observe(frameTime: 50.04, qualifies: true, origin: .debugPoll, at: 1.4)
        var record = RecoveryTraceRecord(id: "s", type: "userSeek", metricsID: nil, startedAt: 1)
        record.record(name: "seekRequested", at: 1)
        record.record(name: "playCalled", at: 1.1)
        record.record(name: "playing", at: 1.3)
        record.record(name: "uiRevealDecision", at: 1.5, fields: ["hasAdvancingRenderedFrames": "true"])
        record.record(name: "videoObservationSummary", at: 1.7, fields: observation.fields)
        record.record(name: "uiReveal", at: 1.7)
        XCTAssertTrue(record.summary.contains("targetVideoAvailableToAdvance=200.0ms"))
        XCTAssertTrue(record.summary.contains("playToVideoAdvanceObserved=300.0ms"))
        XCTAssertTrue(record.summary.contains("playingToVideoAdvanceObserved=100.0ms"))
        XCTAssertTrue(record.summary.contains("videoAdvanceToUIConfirmation=100.0ms"))
        XCTAssertTrue(record.summary.contains("videoAdvanceToUIReveal=300.0ms"))
        XCTAssertTrue(record.summary.contains("videoAvailableOrigin=snapshot"))
        XCTAssertTrue(record.summary.contains("videoAdvancingOrigin=debugPoll"))
    }

    func testSummaryDoesNotInventEvidenceWhenMissingOrAfterReveal() {
        var record = RecoveryTraceRecord(id: "s", type: "userSeek", metricsID: nil, startedAt: 1)
        record.record(name: "seekRequested", at: 1)
        record.record(name: "videoObservationSummary", at: 1.5, fields: RecoveryVideoObservation().fields)
        record.record(name: "uiReveal", at: 1.5)
        XCTAssertTrue(record.summary.contains("targetVideoAvailableToAdvance=-"))
        XCTAssertTrue(record.summary.contains("videoAdvanceToUIReveal=-"))
        XCTAssertTrue(record.summary.contains("videoAdvancingOrigin=-"))
        record.record(name: "videoObservationSummary", at: 2, fields: ["availableAt": "1.2", "advancingAt": "1.8"])
        XCTAssertTrue(record.summary.contains("videoAdvanceToUIReveal=-"))
        XCTAssertTrue(record.summary.contains("targetVideoAvailableToAdvance=600.0ms"))
        XCTAssertEqual(RecoveryVideoObservation().fields["debugPollMaxGapMs"], "-")
    }
}
