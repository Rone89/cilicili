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

    func testStaticTargetFrameAndMissingSamplesNeverAuthorizeMovingVideoReveal() {
        var state = UserSeekRevealSettling()
        for time in [1.0, 1.1, 1.2] {
            XCTAssertFalse(state.observe(frameReady: true, renderedVideoTime: 248.9,
                missingSampleCanContinue: false, requiresAdvancingVideo: true,
                at: time, settleDelay: 0.12))
        }
        XCTAssertFalse(state.observe(frameReady: false, renderedVideoTime: nil,
            missingSampleCanContinue: true, requiresAdvancingVideo: true,
            at: 1.5, settleDelay: 0.12))
        XCTAssertNil(state.readySince)
        XCTAssertFalse(state.hasAdvancingRenderedFrames)
    }

    func testAdvancingTargetFramesStartSettleAndSurviveSamplingGaps() {
        var state = UserSeekRevealSettling()
        _ = state.observe(frameReady: true, renderedVideoTime: 120,
            missingSampleCanContinue: false, requiresAdvancingVideo: true,
            at: 1, settleDelay: 0.12)
        XCTAssertFalse(state.observe(frameReady: true, renderedVideoTime: 120.04,
            missingSampleCanContinue: false, requiresAdvancingVideo: true,
            at: 1.2, settleDelay: 0.12))
        XCTAssertTrue(state.hasAdvancingRenderedFrames)
        XCTAssertEqual(state.readySince, 1.2)
        XCTAssertTrue(state.observe(frameReady: false, renderedVideoTime: nil,
            missingSampleCanContinue: true, requiresAdvancingVideo: true,
            at: 1.4, settleDelay: 0.12))
        state.reset()
        XCTAssertFalse(state.hasAdvancingRenderedFrames)
        XCTAssertFalse(state.observe(frameReady: true, renderedVideoTime: 120.08,
            missingSampleCanContinue: false, requiresAdvancingVideo: true,
            at: 2, settleDelay: 0.12))
    }

    func testTimestampRegressionRestartsMotionVerification() {
        var state = UserSeekRevealSettling()
        _ = state.observe(frameReady: true, renderedVideoTime: 120,
            missingSampleCanContinue: false, requiresAdvancingVideo: true,
            at: 1, settleDelay: 0.12)
        _ = state.observe(frameReady: true, renderedVideoTime: 120.04,
            missingSampleCanContinue: false, requiresAdvancingVideo: true,
            at: 1.1, settleDelay: 0.12)
        XCTAssertFalse(state.observe(frameReady: true, renderedVideoTime: 119.9,
            missingSampleCanContinue: false, requiresAdvancingVideo: true,
            at: 1.3, settleDelay: 0.12))
        XCTAssertNil(state.readySince)
        XCTAssertFalse(state.hasAdvancingRenderedFrames)
    }

    func testNaturalForwardMotionPreservesSettleAfterLeavingTargetWindow() {
        var state = UserSeekRevealSettling()
        _ = state.observe(frameReady: true, renderedVideoTime: 90.2667,
            missingSampleCanContinue: false, requiresAdvancingVideo: true,
            at: 0.255, settleDelay: 0.12)
        _ = state.observe(frameReady: true, renderedVideoTime: 90.3,
            missingSampleCanContinue: false, requiresAdvancingVideo: true,
            at: 0.575, settleDelay: 0.12)
        XCTAssertFalse(state.observe(frameReady: true, renderedVideoTime: 90.4333,
            missingSampleCanContinue: false, requiresAdvancingVideo: true,
            at: 0.6944276, settleDelay: 0.12))
        let canContinue = state.canContinueAdvancingFrame(renderedVideoTime: 90.5333,
            currentTime: 90.5602, isPlaying: true, playbackRate: 1, at: 0.812)
        XCTAssertTrue(canContinue)
        XCTAssertTrue(state.observe(frameReady: canContinue, renderedVideoTime: 90.5333,
            missingSampleCanContinue: false, requiresAdvancingVideo: true,
            at: 0.812, settleDelay: 0.12))
        XCTAssertEqual(state.readySince, 0.575)
    }

    func testProgressionRequiresVerifiedAdvancingTargetAndResetsForNewSeek() {
        var state = UserSeekRevealSettling()
        func allowed(_ state: UserSeekRevealSettling) -> Bool {
            state.canContinueAdvancingFrame(renderedVideoTime: 30.6, currentTime: 30.6,
                isPlaying: true, playbackRate: 1, at: 1.3)
        }
        XCTAssertFalse(allowed(state))
        _ = state.observe(frameReady: true, renderedVideoTime: 30.3,
            missingSampleCanContinue: false, requiresAdvancingVideo: true,
            at: 1, settleDelay: 0.12)
        XCTAssertFalse(allowed(state), "One static target frame cannot authorize continuation")
        _ = state.observe(frameReady: true, renderedVideoTime: 30.4,
            missingSampleCanContinue: false, requiresAdvancingVideo: true,
            at: 1.1, settleDelay: 0.12)
        XCTAssertTrue(allowed(state))
        state.reset()
        XCTAssertFalse(allowed(state), "A new seek cannot inherit the previous target's motion")
    }

    func testProgressionRejectsBackwardFramesJumpsAndPlayheadMismatch() {
        var state = UserSeekRevealSettling()
        _ = state.observe(frameReady: true, renderedVideoTime: 30.3,
            missingSampleCanContinue: false, requiresAdvancingVideo: true,
            at: 1, settleDelay: 0.12)
        _ = state.observe(frameReady: true, renderedVideoTime: 30.4,
            missingSampleCanContinue: false, requiresAdvancingVideo: true,
            at: 1.1, settleDelay: 0.12)
        func allowed(frame: Double? = 30.6, playhead: Double? = 30.6,
                     playing: Bool = true, rate: Double = 1, now: Double = 1.3) -> Bool {
            state.canContinueAdvancingFrame(renderedVideoTime: frame, currentTime: playhead,
                isPlaying: playing, playbackRate: rate, at: now)
        }
        XCTAssertTrue(allowed())
        XCTAssertFalse(allowed(frame: 30.39, playhead: 30.39))
        XCTAssertFalse(allowed(frame: 10, playhead: 10))
        XCTAssertFalse(allowed(frame: 40, playhead: 40))
        XCTAssertFalse(allowed(playhead: 32))
        XCTAssertFalse(allowed(frame: nil))
        XCTAssertFalse(allowed(frame: .nan))
        XCTAssertFalse(allowed(playhead: nil))
        XCTAssertFalse(allowed(playhead: .infinity))
        XCTAssertFalse(allowed(playing: false))
        XCTAssertFalse(allowed(rate: 0))
        XCTAssertFalse(allowed(rate: .nan))
        XCTAssertFalse(allowed(now: 0.9))
        XCTAssertFalse(allowed(now: .nan))
        let rejected = allowed(frame: 40, playhead: 40)
        XCTAssertFalse(state.observe(frameReady: rejected, renderedVideoTime: 40,
            missingSampleCanContinue: false, requiresAdvancingVideo: true,
            at: 1.3, settleDelay: 0.12))
        XCTAssertNil(state.readySince)
        XCTAssertFalse(state.hasAdvancingRenderedFrames)
    }

    func testForwardMotionAllowanceUsesPlaybackRateAndOriginalAnchor() {
        var state = UserSeekRevealSettling()
        _ = state.observe(frameReady: true, renderedVideoTime: 30.3,
            missingSampleCanContinue: false, requiresAdvancingVideo: true,
            at: 1, settleDelay: 0.12)
        _ = state.observe(frameReady: true, renderedVideoTime: 30.4,
            missingSampleCanContinue: false, requiresAdvancingVideo: true,
            at: 1.1, settleDelay: 0.12)
        XCTAssertTrue(state.canContinueAdvancingFrame(renderedVideoTime: 31.2, currentTime: 31.2,
            isPlaying: true, playbackRate: 2, at: 1.3))
        XCTAssertFalse(state.canContinueAdvancingFrame(renderedVideoTime: 31.2, currentTime: 31.2,
            isPlaying: true, playbackRate: 1, at: 1.3))
        XCTAssertFalse(state.canContinueAdvancingFrame(renderedVideoTime: 31.2, currentTime: 31.2,
            isPlaying: true, playbackRate: 0.5, at: 1.3))
        _ = state.observe(frameReady: true, renderedVideoTime: 31.2,
            missingSampleCanContinue: false, requiresAdvancingVideo: true,
            at: 1.3, settleDelay: 0.12)
        XCTAssertFalse(state.canContinueAdvancingFrame(renderedVideoTime: 32, currentTime: 32,
            isPlaying: true, playbackRate: 2, at: 1.4), "Repeated samples must not extend the original motion budget")
    }
}
