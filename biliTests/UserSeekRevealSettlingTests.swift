import XCTest
@testable import bili

final class UserSeekRevealSettlingTests: XCTestCase {
    func testMissingSamplesPreserveVerifiedTargetThroughOriginalSettleWindow() {
        var state = UserSeekRevealSettling()
        XCTAssertFalse(state.observe(frameReady: true, renderedVideoTime: 612.43,
            missingSampleCanContinue: false, at: 1, settleDelay: 0.12))
        XCTAssertFalse(state.observe(frameReady: false, renderedVideoTime: nil,
            missingSampleCanContinue: true, at: 1.06, settleDelay: 0.12))
        XCTAssertEqual(state.readySince, 1)
        XCTAssertTrue(state.observe(frameReady: false, renderedVideoTime: nil,
            missingSampleCanContinue: true, at: 1.13, settleDelay: 0.12))
        XCTAssertEqual(state.readySince, 1)
    }

    func testMissingSampleNeverStartsWindowWithoutVerifiedTarget() {
        var state = UserSeekRevealSettling()
        XCTAssertFalse(state.observe(frameReady: false, renderedVideoTime: nil,
            missingSampleCanContinue: true, at: 5, settleDelay: 0.12))
        XCTAssertNil(state.readySince)
    }

    func testNonVideoReadinessDoesNotAuthorizeMissingVideoSample() {
        var state = UserSeekRevealSettling()
        _ = state.observe(frameReady: true, renderedVideoTime: nil,
            missingSampleCanContinue: false, at: 1, settleDelay: 0.12)
        XCTAssertFalse(state.observe(frameReady: false, renderedVideoTime: nil,
            missingSampleCanContinue: true, at: 1.2, settleDelay: 0.12))
        XCTAssertNil(state.readySince)
    }

    func testExplicitWrongFrameInvalidatesPreviouslyVerifiedTarget() {
        var state = UserSeekRevealSettling()
        _ = state.observe(frameReady: true, renderedVideoTime: 120,
            missingSampleCanContinue: false, at: 1, settleDelay: 0.12)
        XCTAssertFalse(state.observe(frameReady: false, renderedVideoTime: 10,
            missingSampleCanContinue: true, at: 1.1, settleDelay: 0.12))
        XCTAssertNil(state.readySince)
        XCTAssertFalse(state.observe(frameReady: false, renderedVideoTime: nil,
            missingSampleCanContinue: true, at: 1.3, settleDelay: 0.12))
    }

    func testPausedOrOutOfWindowSampleResetsEvidence() {
        var state = UserSeekRevealSettling()
        _ = state.observe(frameReady: true, renderedVideoTime: 120,
            missingSampleCanContinue: false, at: 1, settleDelay: 0.12)
        XCTAssertFalse(state.observe(frameReady: false, renderedVideoTime: nil,
            missingSampleCanContinue: false, at: 1.2, settleDelay: 0.12))
        XCTAssertNil(state.readySince)
    }

    func testNewSeekWithSameTargetCannotReusePriorEvidence() {
        var state = UserSeekRevealSettling()
        _ = state.observe(frameReady: true, renderedVideoTime: 120,
            missingSampleCanContinue: false, at: 1, settleDelay: 0.12)
        state.reset()
        XCTAssertFalse(state.observe(frameReady: false, renderedVideoTime: nil,
            missingSampleCanContinue: true, at: 1.3, settleDelay: 0.12))
        XCTAssertFalse(state.observe(frameReady: true, renderedVideoTime: 120,
            missingSampleCanContinue: false, at: 1.4, settleDelay: 0.12))
        XCTAssertEqual(state.readySince, 1.4)
    }

    func testInvalidPresentFrameCannotBeTreatedAsMissingSample() {
        var state = UserSeekRevealSettling()
        _ = state.observe(frameReady: true, renderedVideoTime: 120,
            missingSampleCanContinue: false, at: 1, settleDelay: 0.12)
        XCTAssertFalse(state.observe(frameReady: false, renderedVideoTime: .nan,
            missingSampleCanContinue: true, at: 1.2, settleDelay: 0.12))
        XCTAssertNil(state.readySince)
    }
    func testMissingSampleContinuationRequiresAllPlaybackGuards() {
        func allowed(rendered: Double? = nil, required: Bool = true,
                     playing: Bool = true, time: Double? = 120, near: Bool = true) -> Bool {
            UserSeekRevealSettling.canContinueMissingSample(
                renderedVideoTime: rendered, requiresRenderedVideoTime: required,
                isPlaying: playing, currentTime: time, playbackTimeNearTarget: near)
        }
        XCTAssertTrue(allowed())
        XCTAssertFalse(allowed(rendered: 120))
        XCTAssertFalse(allowed(rendered: .nan))
        XCTAssertFalse(allowed(required: false))
        XCTAssertFalse(allowed(playing: false))
        XCTAssertFalse(allowed(time: nil))
        XCTAssertFalse(allowed(time: .nan))
        XCTAssertFalse(allowed(time: .infinity))
        XCTAssertFalse(allowed(time: -1))
        XCTAssertFalse(allowed(near: false))
    }

}
