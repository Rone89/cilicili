import XCTest

@testable import bili

@MainActor
final class VideoDetailNavigationLatencyReportFormatterTests: XCTestCase {
    func testCopyTextSeparatesEntryAndBackLatencyFromUserActions() {
        let snapshot = makeSnapshot(
            durationMilliseconds: 2_790,
            events: [
                event(.navigationRequested, elapsed: 0, delta: 0, detail: "group=formal"),
                event(.pageAppeared, elapsed: 30, delta: 30),
                event(.viewControllerAppeared, elapsed: 585, delta: 555),
                event(.firstFramePresented, elapsed: 1_300, delta: 715),
                event(.navigationBackRequested, elapsed: 2_200, delta: 900, detail: "source=gesture"),
                event(.pageDisappeared, elapsed: 2_790, delta: 590),
            ]
        )

        let report = VideoDetailNavigationLatencyReportFormatter.copyText([snapshot])

        XCTAssertTrue(report.contains("group=正式策略"))
        XCTAssertTrue(report.contains("viewControllerAppeared phase=585ms elapsed=585ms"))
        XCTAssertTrue(report.contains("firstFramePresented phase=1300ms elapsed=1300ms"))
        XCTAssertTrue(report.contains("navigationBackRequested action elapsed=2200ms source=gesture"))
        XCTAssertTrue(report.contains("pageDisappeared back=590ms elapsed=2790ms"))
        XCTAssertFalse(report.contains("navigationBackRequested action elapsed=2200ms slow"))
    }

    func testCopyTextDoesNotTreatPageDwellAsNavigationLatency() {
        let snapshot = makeSnapshot(
            durationMilliseconds: 4_000,
            events: [
                event(.navigationRequested, elapsed: 0, delta: 0),
                event(.firstFramePresented, elapsed: 900, delta: 900),
                event(.pageDisappeared, elapsed: 4_000, delta: 3_100),
            ]
        )

        let report = VideoDetailNavigationLatencyReportFormatter.copyText([snapshot])

        XCTAssertTrue(report.contains("pageDisappeared dwell=3100ms elapsed=4000ms"))
        XCTAssertFalse(report.contains("pageDisappeared dwell=3100ms elapsed=4000ms slow"))
    }

    func testCopyTextUsesRecordedBackToVisibleDuration() {
        let snapshot = makeSnapshot(
            durationMilliseconds: 2_100,
            events: [
                event(.navigationRequested, elapsed: 0, delta: 0),
                event(.returnedPageVisible, elapsed: 2_100, delta: 1_700, detail: "backToVisible=240ms"),
            ]
        )

        let report = VideoDetailNavigationLatencyReportFormatter.copyText([snapshot])

        XCTAssertTrue(report.contains("returnedPageVisible back=240ms elapsed=2100ms"))
    }

    func testCopyTextMeasuresBackgroundResumeFromReturnBoundary() {
        let snapshot = makeSnapshot(
            durationMilliseconds: 5_000,
            events: [
                event(.navigationRequested, elapsed: 0, delta: 0),
                event(.returnedPageVisible, elapsed: 4_800, delta: 3_900, detail: "backToVisible=240ms"),
                event(.backgroundRenderFreezeReleased, elapsed: 5_000, delta: 200),
            ]
        )

        let report = VideoDetailNavigationLatencyReportFormatter.copyText([snapshot])

        XCTAssertTrue(
            report.contains("backgroundRenderFreezeReleased resume=200ms elapsed=5000ms")
        )
        XCTAssertFalse(report.contains("backgroundRenderFreezeReleased phase=5000ms"))
    }

    func testCopyTextDoesNotGuessMissingBackToVisibleDuration() {
        let snapshot = makeSnapshot(
            durationMilliseconds: 2_100,
            events: [
                event(.navigationRequested, elapsed: 0, delta: 0),
                event(.returnedPageVisible, elapsed: 2_100, delta: 1_700),
            ]
        )

        let report = VideoDetailNavigationLatencyReportFormatter.copyText([snapshot])

        XCTAssertTrue(report.contains("returnedPageVisible back=unknown elapsed=2100ms"))
        XCTAssertFalse(report.contains("returnedPageVisible back=unknown elapsed=2100ms slow"))
    }

    func testCopyTextDoesNotReuseBackRequestAfterPageBecameVisibleAgain() {
        let snapshot = makeSnapshot(
            durationMilliseconds: 16_291,
            events: [
                event(.navigationRequested, elapsed: 0, delta: 0),
                event(.navigationBackRequested, elapsed: 3_386, delta: 2_267),
                event(.returnedPageVisible, elapsed: 4_380, delta: 994, detail: "backToVisible=993ms"),
                event(.pageDisappeared, elapsed: 16_291, delta: 11_911),
            ]
        )

        let report = VideoDetailNavigationLatencyReportFormatter.copyText([snapshot])

        XCTAssertTrue(report.contains("pageDisappeared dwell=11911ms elapsed=16291ms"))
        XCTAssertFalse(report.contains("pageDisappeared back=12905ms"))
        XCTAssertFalse(report.contains("pageDisappeared dwell=11911ms elapsed=16291ms slow"))
    }

    func testCopyTextUsesEventOrderWhenBackAndVisibleHaveEqualTimestamps() {
        let snapshot = makeSnapshot(
            durationMilliseconds: 200,
            events: [
                event(.returnedPageVisible, elapsed: 100, delta: 100, detail: "backToVisible=100ms"),
                event(.navigationBackRequested, elapsed: 100, delta: 0),
                event(.pageDisappeared, elapsed: 200, delta: 100),
            ]
        )

        let report = VideoDetailNavigationLatencyReportFormatter.copyText([snapshot])

        XCTAssertTrue(report.contains("pageDisappeared back=100ms elapsed=200ms"))
        XCTAssertFalse(report.contains("pageDisappeared dwell=100ms"))
    }

    private func makeSnapshot(
        durationMilliseconds: Int,
        events: [PlaybackDetailPerformanceEventRecord]
    ) -> PlaybackDetailPerformanceSnapshot {
        PlaybackDetailPerformanceSnapshot(
            context: PlaybackDetailPerformanceContext(
                kind: .video,
                pageID: "BV1Diagnostic",
                mediaID: "BV1Diagnostic",
                title: "诊断样本"
            ),
            durationMilliseconds: durationMilliseconds,
            events: events
        )
    }

    private func event(
        _ milestone: PlaybackDetailPerformanceMilestone,
        elapsed: Int,
        delta: Int,
        detail: String? = nil
    ) -> PlaybackDetailPerformanceEventRecord {
        PlaybackDetailPerformanceEventRecord(
            milestone: milestone,
            elapsedMilliseconds: elapsed,
            deltaMilliseconds: delta,
            detail: detail
        )
    }
}
