import XCTest
@testable import bili

final class PlaybackRecoveryRevealDiagnosticsTests: XCTestCase {
    func testBlockedSurfaceSettleAndReadyTransitions() {
        var state = RecoveryRevealDiagnosticState()

        let blocked = state.transition(
            decision: "blocked", reason: "surfaceBlack", at: 1.0,
            fields: ["surface": "black"]
        )
        XCTAssertEqual(blocked?["decision"], "blocked")
        XCTAssertEqual(blocked?["reason"], "surfaceBlack")
        XCTAssertEqual(blocked?["checkCount"], "1")
        XCTAssertEqual(blocked?["resetCount"], "0")
        XCTAssertNil(blocked?["previousDecisionElapsedMs"])

        let settleStarted = state.transition(
            decision: "settleStarted", reason: "surfaceBlack", at: 1.25,
            fields: ["phase": "start"]
        )
        XCTAssertEqual(settleStarted?["previousDecisionElapsedMs"], "250.0")

        let settling = state.transition(
            decision: "settling", reason: "surfaceBlack", at: 1.5,
            fields: ["phase": "wait"]
        )
        XCTAssertEqual(settling?["previousDecisionElapsedMs"], "250.0")

        let ready = state.transition(
            decision: "ready", reason: "surfaceVisible", at: 1.75,
            fields: ["phase": "ready"]
        )
        XCTAssertEqual(ready?["previousDecisionElapsedMs"], "250.0")
    }

    func testRepeatedDecisionAndReasonIsSuppressed() {
        var state = RecoveryRevealDiagnosticState()
        XCTAssertNotNil(state.transition(decision: "blocked", reason: "surfaceBlack", at: 1, fields: [:]))
        XCTAssertNil(state.transition(decision: "blocked", reason: "surfaceBlack", at: 2, fields: ["ignored": "yes"]))

        let changed = state.transition(decision: "blocked", reason: "timeout", at: 3, fields: [:])
        XCTAssertEqual(changed?["checkCount"], "3")
        XCTAssertEqual(changed?["previousDecisionElapsedMs"], "2000.0")
    }

    func testBlockedAfterSettlingResetsCheckCount() {
        var state = RecoveryRevealDiagnosticState()
        _ = state.transition(decision: "blocked", reason: "surfaceBlack", at: 1, fields: [:])
        _ = state.transition(decision: "settleStarted", reason: "surfaceBlack", at: 2, fields: [:])

        let resetAfterStart = state.transition(decision: "blocked", reason: "surfaceBlack", at: 3, fields: [:])
        XCTAssertEqual(resetAfterStart?["checkCount"], "1")
        XCTAssertEqual(resetAfterStart?["resetCount"], "1")

        _ = state.transition(decision: "settling", reason: "surfaceBlack", at: 4, fields: [:])
        let resetAfterSettling = state.transition(decision: "blocked", reason: "surfaceBlack", at: 5, fields: [:])
        XCTAssertEqual(resetAfterSettling?["checkCount"], "1")
        XCTAssertEqual(resetAfterSettling?["resetCount"], "2")
    }

    func testTimeoutFallbackAndMissingFieldsStayUnknown() {
        var state = RecoveryRevealDiagnosticState()
        let output = state.transition(
            decision: "timeoutFallback", reason: "timeout", at: 10,
            fields: [:]
        )

        XCTAssertEqual(output?["decision"], "timeoutFallback")
        XCTAssertEqual(output?["reason"], "timeout")
        XCTAssertEqual(output?["checkCount"], "1")
        XCTAssertEqual(output?["resetCount"], "0")
        XCTAssertNil(output?["bufferAhead"])
        XCTAssertNil(output?["targetTime"])
        XCTAssertNil(output?["previousDecisionElapsedMs"])
    }
}
