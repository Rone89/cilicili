import XCTest
@testable import bili

final class ManualResumeRecoveryTimingTests: XCTestCase {
    func testSeparatesPauseToPlayTransportAndFreshFrameTimings() {
        var timing = ManualResumeRecoveryTiming(pausedAt: 1, baselineRenderedVideoTime: 30)!
        XCTAssertEqual(timing.beginPlay(at: 1.4) ?? -1, 400, accuracy: 0.0001)

        let transport = timing.observeTransportPlaying(at: 1.55)
        XCTAssertEqual(transport?.pauseToPlayMilliseconds ?? -1, 400, accuracy: 0.0001)
        XCTAssertEqual(transport?.playToTransportMilliseconds ?? -1, 150, accuracy: 0.0001)

        XCTAssertNil(timing.observeFreshFrame(30.008, at: 1.6), "The existing 8 ms threshold excludes noise")
        let frame = timing.observeFreshFrame(30.04, at: 1.7)
        XCTAssertEqual(frame?.pauseToFrameMilliseconds ?? -1, 700, accuracy: 0.0001)
        XCTAssertEqual(frame?.playToFrameMilliseconds ?? -1, 300, accuracy: 0.0001)
    }

    func testFreshFrameRequiresBaselinePlayTransportAndForwardMediaTime() {
        var timing = ManualResumeRecoveryTiming(pausedAt: 1, baselineRenderedVideoTime: 30)!
        XCTAssertNil(timing.observeFreshFrame(30.5, at: 1.1))
        _ = timing.beginPlay(at: 1.2)
        XCTAssertNil(timing.observeFreshFrame(30.5, at: 1.3))
        _ = timing.observeTransportPlaying(at: 1.4)
        XCTAssertNil(timing.observeFreshFrame(30, at: 1.5))
        XCTAssertNil(timing.observeFreshFrame(29, at: 1.5))
        XCTAssertNil(timing.observeFreshFrame(.nan, at: 1.5))
        XCTAssertNil(timing.observeFreshFrame(30.5, at: 1.3), "Queued earlier samples cannot count as a resumed frame")
        XCTAssertNotNil(timing.observeFreshFrame(30.5, at: 1.5))
    }

    func testMissingBaselineCannotClaimFreshFrame() {
        var timing = ManualResumeRecoveryTiming(pausedAt: 1, baselineRenderedVideoTime: nil)!
        _ = timing.beginPlay(at: 1.1)
        _ = timing.observeTransportPlaying(at: 1.2)
        XCTAssertNil(timing.observeFreshFrame(30.5, at: 1.3))
    }

    func testRejectsInvalidAndOutOfOrderTimes() {
        XCTAssertNil(ManualResumeRecoveryTiming(pausedAt: .nan, baselineRenderedVideoTime: 30))
        XCTAssertNil(ManualResumeRecoveryTiming(pausedAt: 1, baselineRenderedVideoTime: .infinity))
        var timing = ManualResumeRecoveryTiming(pausedAt: 1, baselineRenderedVideoTime: 30)!
        XCTAssertNil(timing.beginPlay(at: .infinity))
        XCTAssertNil(timing.beginPlay(at: 0.9))
        XCTAssertEqual(timing.beginPlay(at: 1.1) ?? -1, 100, accuracy: 0.0001)
        XCTAssertNil(timing.observeTransportPlaying(at: 1))
        XCTAssertNotNil(timing.observeTransportPlaying(at: 1.2))
        XCTAssertNil(timing.observeTransportPlaying(at: 1.3), "Transport start is recorded once")
    }
}
