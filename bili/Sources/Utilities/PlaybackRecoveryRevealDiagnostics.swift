nonisolated struct RecoveryRevealDiagnosticState: Sendable {
    private var lastDecision: String?
    private var lastReason: String?
    private var lastAt: Double?
    private var checkCount = 0
    private var resetCount = 0

    init() {}

    mutating func transition(
        decision: String,
        reason: String,
        at: Double,
        fields: [String: String]
    ) -> [String: String]? {
        let previousAt = lastAt
        let elapsed = previousAt.map { at - $0 }
        let changed = decision != lastDecision || reason != lastReason

        checkCount += 1
        if decision == "blocked",
           lastDecision == "settleStarted" || lastDecision == "settling" {
            checkCount = 1
            resetCount += 1
        }

        lastDecision = decision
        lastReason = reason
        guard changed else { return nil }
        lastAt = at

        var output = fields
        output["decision"] = decision
        output["reason"] = reason
        output["checkCount"] = String(checkCount)
        output["resetCount"] = String(resetCount)
        if let elapsed, elapsed.isFinite, elapsed >= 0 {
            output["previousDecisionElapsedMs"] = recoveryRevealMilliseconds(elapsed)
        }
        return output
    }
}

private nonisolated func recoveryRevealMilliseconds(_ seconds: Double) -> String {
    let milliseconds = (seconds * 1_000 * 1_000).rounded() / 1_000
    return String(milliseconds)
}
