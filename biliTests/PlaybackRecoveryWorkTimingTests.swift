import XCTest
@testable import bili

final class PlaybackRecoveryWorkTimingTests: XCTestCase {
    func testWorkTimingAggregatesDurationsWithOneDecimalMilliseconds() {
        var timing = RecoveryWorkTiming()
        timing.record(startedAt: 10, completedAt: 10.25)
        timing.record(startedAt: 20, completedAt: 20.5)

        let fields = timing.fields(prefix: "reload")
        XCTAssertEqual(fields["reloadCount"], "2")
        XCTAssertEqual(fields["reloadTotalMs"], "750.0")
        XCTAssertEqual(fields["reloadMeanMs"], "375.0")
        XCTAssertEqual(fields["reloadMaxMs"], "500.0")
    }

    func testWorkTimingReportsZeroAndMissingMeasurements() {
        var zero = RecoveryWorkTiming()
        zero.record(startedAt: 3, completedAt: 3)
        XCTAssertEqual(
            zero.fields(prefix: "work"),
            [
                "workCount": "1",
                "workTotalMs": "0.0",
                "workMeanMs": "0.0",
                "workMaxMs": "0.0",
            ]
        )

        let missing = RecoveryWorkTiming().fields(prefix: "work")
        XCTAssertEqual(missing["workCount"], "0")
        XCTAssertEqual(missing["workTotalMs"], "-")
        XCTAssertEqual(missing["workMeanMs"], "-")
        XCTAssertEqual(missing["workMaxMs"], "-")
    }

    func testWorkTimingIgnoresInvalidAndBackwardMeasurements() {
        var timing = RecoveryWorkTiming()
        timing.record(startedAt: .nan, completedAt: 2)
        timing.record(startedAt: 1, completedAt: .infinity)
        timing.record(startedAt: 4, completedAt: 3)
        timing.record(startedAt: 5, completedAt: 5.1)

        let fields = timing.fields(prefix: "work")
        XCTAssertEqual(fields["workCount"], "1")
        XCTAssertEqual(fields["workTotalMs"], "100.0")
        XCTAssertEqual(fields["workMeanMs"], "100.0")
        XCTAssertEqual(fields["workMaxMs"], "100.0")
    }

    func testRevealTimingCapturesDeadlineOvershootAndSettledEvaluation() {
        var timing = RecoveryRevealTiming()
        timing.recordEvaluation(
            startedAt: 100,
            completedAt: 100.01,
            readySince: 100,
            settleDelay: 0.5,
            settled: false
        )
        timing.recordEvaluation(
            startedAt: 100.7,
            completedAt: 100.71,
            readySince: 100,
            settleDelay: 0.5,
            settled: true
        )

        let fields = timing.fields
        XCTAssertEqual(fields["uiEvaluationCount"], "2")
        XCTAssertEqual(fields["uiEvaluationMaxGapMs"], "700.0")
        XCTAssertEqual(fields["settleDeadlineAt"], "100.5")
        XCTAssertEqual(fields["settleFirstCheckAfterDeadlineAt"], "100.7")
        XCTAssertEqual(fields["settleDeadlineOvershootMs"], "200.0")
        XCTAssertEqual(fields["settleReadyEvaluationAt"], "100.7")
    }

    func testRevealTimingDoesNotInventEvidenceBeforeDeadline() {
        var timing = RecoveryRevealTiming()
        timing.recordEvaluation(
            startedAt: 10.25,
            completedAt: 10.3,
            readySince: 10,
            settleDelay: 1,
            settled: false
        )

        let fields = timing.fields
        XCTAssertEqual(fields["settleDeadlineAt"], "11.0")
        XCTAssertEqual(fields["settleFirstCheckAfterDeadlineAt"], "-")
        XCTAssertEqual(fields["settleDeadlineOvershootMs"], "-")
        XCTAssertEqual(fields["settleReadyEvaluationAt"], "-")
    }

    func testRevealTimingResetsEvidenceForNewAndNilWindows() {
        var timing = RecoveryRevealTiming()
        timing.recordEvaluation(
            startedAt: 1,
            completedAt: 1.01,
            readySince: 1,
            settleDelay: 1,
            settled: false
        )
        timing.recordEvaluation(
            startedAt: 2.2,
            completedAt: 2.21,
            readySince: 1,
            settleDelay: 1,
            settled: true
        )
        XCTAssertEqual(timing.fields["settleFirstCheckAfterDeadlineAt"], "2.2")

        timing.recordEvaluation(
            startedAt: 5,
            completedAt: 5.01,
            readySince: 5,
            settleDelay: 1,
            settled: false
        )
        XCTAssertEqual(timing.fields["settleDeadlineAt"], "6.0")
        XCTAssertEqual(timing.fields["settleFirstCheckAfterDeadlineAt"], "-")
        XCTAssertEqual(timing.fields["settleDeadlineOvershootMs"], "-")
        XCTAssertEqual(timing.fields["settleReadyEvaluationAt"], "-")

        timing.recordEvaluation(
            startedAt: 6.1,
            completedAt: 6.11,
            readySince: nil,
            settleDelay: 1,
            settled: true
        )
        XCTAssertEqual(timing.fields["settleDeadlineAt"], "-")
        XCTAssertEqual(timing.fields["settleFirstCheckAfterDeadlineAt"], "-")
        XCTAssertEqual(timing.fields["settleDeadlineOvershootMs"], "-")
        XCTAssertEqual(timing.fields["settleReadyEvaluationAt"], "-")
    }

    func testRevealTimingIgnoresInvalidAndBackwardEvaluations() {
        var timing = RecoveryRevealTiming()
        timing.recordEvaluation(
            startedAt: 10,
            completedAt: 10.1,
            readySince: 10,
            settleDelay: 0.5,
            settled: false
        )
        timing.recordEvaluation(
            startedAt: 9,
            completedAt: 9.1,
            readySince: nil,
            settleDelay: 0,
            settled: true
        )
        timing.recordEvaluation(
            startedAt: 10.2,
            completedAt: 10.3,
            readySince: 10,
            settleDelay: -0.1,
            settled: true
        )
        timing.recordEvaluation(
            startedAt: .nan,
            completedAt: 11,
            readySince: 10,
            settleDelay: 0.5,
            settled: true
        )
        timing.recordEvaluation(
            startedAt: 10.6,
            completedAt: 10.7,
            readySince: 10,
            settleDelay: 0.5,
            settled: true
        )

        let fields = timing.fields
        XCTAssertEqual(fields["uiEvaluationCount"], "2")
        XCTAssertEqual(fields["uiEvaluationMaxGapMs"], "600.0")
        XCTAssertEqual(fields["settleFirstCheckAfterDeadlineAt"], "10.6")
        XCTAssertEqual(fields["settleDeadlineOvershootMs"], "100.0")
        XCTAssertEqual(fields["settleReadyEvaluationAt"], "10.6")
    }
}
