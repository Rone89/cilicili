import Foundation

private nonisolated func playbackRecoveryTimingMilliseconds(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "-" }
    return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
}

private nonisolated func playbackRecoveryTimingTimestamp(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "-" }
    return String(value)
}

nonisolated struct RecoveryWorkTiming: Sendable {
    private var count = 0
    private var totalMilliseconds = 0.0
    private var maximumMilliseconds: Double?

    init() {}

    mutating func record(startedAt: Double, completedAt: Double) {
        guard startedAt.isFinite, completedAt.isFinite, completedAt >= startedAt else { return }

        let milliseconds = (completedAt - startedAt) * 1_000
        guard milliseconds.isFinite else { return }

        let newTotal = totalMilliseconds + milliseconds
        guard newTotal.isFinite else { return }

        count += 1
        totalMilliseconds = newTotal
        maximumMilliseconds = max(maximumMilliseconds ?? milliseconds, milliseconds)
    }

    func fields(prefix: String) -> [String: String] {
        let countKey = "\(prefix)Count"
        let totalKey = "\(prefix)TotalMs"
        let meanKey = "\(prefix)MeanMs"
        let maxKey = "\(prefix)MaxMs"
        guard count > 0 else {
            return [
                countKey: "0",
                totalKey: "-",
                meanKey: "-",
                maxKey: "-",
            ]
        }

        return [
            countKey: String(count),
            totalKey: playbackRecoveryTimingMilliseconds(totalMilliseconds),
            meanKey: playbackRecoveryTimingMilliseconds(totalMilliseconds / Double(count)),
            maxKey: playbackRecoveryTimingMilliseconds(maximumMilliseconds),
        ]
    }
}

nonisolated struct RecoveryRevealTiming: Sendable {
    private var evaluationTiming = RecoveryWorkTiming()
    private var previousEvaluationStartedAt: Double?
    private var maximumEvaluationStartGapMilliseconds: Double?

    private var currentReadySince: Double?
    private var currentSettleDeadlineAt: Double?
    private var settleFirstCheckAfterDeadlineAt: Double?
    private var settleDeadlineOvershootMilliseconds: Double?
    private var settleReadyEvaluationAt: Double?

    init() {}

    mutating func recordEvaluation(
        startedAt: Double,
        completedAt: Double,
        readySince: Double?,
        settleDelay: Double,
        settled: Bool
    ) {
        guard startedAt.isFinite, completedAt.isFinite, completedAt >= startedAt,
              settleDelay.isFinite, settleDelay >= 0, readySince.map(\.isFinite) ?? true else { return }

        let workMilliseconds = (completedAt - startedAt) * 1_000
        guard workMilliseconds.isFinite else { return }

        var startGapMilliseconds: Double?
        if let previousEvaluationStartedAt {
            guard startedAt >= previousEvaluationStartedAt else { return }
            let gapMilliseconds = (startedAt - previousEvaluationStartedAt) * 1_000
            guard gapMilliseconds.isFinite else { return }
            startGapMilliseconds = gapMilliseconds
        }

        let settleDeadlineAt: Double?
        if let readySince {
            let deadline = readySince + settleDelay
            guard deadline.isFinite else { return }
            settleDeadlineAt = deadline
        } else {
            settleDeadlineAt = nil
        }

        var overshootMilliseconds: Double?
        if let settleDeadlineAt, startedAt >= settleDeadlineAt {
            let overshoot = (startedAt - settleDeadlineAt) * 1_000
            guard overshoot.isFinite else { return }
            overshootMilliseconds = overshoot
        }

        previousEvaluationStartedAt = startedAt
        evaluationTiming.record(startedAt: startedAt, completedAt: completedAt)
        if let startGapMilliseconds {
            maximumEvaluationStartGapMilliseconds = max(maximumEvaluationStartGapMilliseconds ?? startGapMilliseconds, startGapMilliseconds)
        }

        guard let settleDeadlineAt, let readySince else {
            currentReadySince = nil
            currentSettleDeadlineAt = nil
            resetSettleEvidence()
            return
        }

        if currentReadySince != readySince || currentSettleDeadlineAt != settleDeadlineAt {
            currentReadySince = readySince
            currentSettleDeadlineAt = settleDeadlineAt
            resetSettleEvidence()
        }

        if settleFirstCheckAfterDeadlineAt == nil, let overshootMilliseconds {
            settleFirstCheckAfterDeadlineAt = startedAt
            settleDeadlineOvershootMilliseconds = overshootMilliseconds
        }
        if settled, settleReadyEvaluationAt == nil {
            settleReadyEvaluationAt = startedAt
        }
    }

    var fields: [String: String] {
        var fields = evaluationTiming.fields(prefix: "uiEvaluation")
        fields["uiEvaluationMaxGapMs"] = playbackRecoveryTimingMilliseconds(maximumEvaluationStartGapMilliseconds)
        fields["settleDeadlineAt"] = playbackRecoveryTimingTimestamp(currentSettleDeadlineAt)
        fields["settleFirstCheckAfterDeadlineAt"] = playbackRecoveryTimingTimestamp(settleFirstCheckAfterDeadlineAt)
        fields["settleDeadlineOvershootMs"] = playbackRecoveryTimingMilliseconds(settleDeadlineOvershootMilliseconds)
        fields["settleReadyEvaluationAt"] = playbackRecoveryTimingTimestamp(settleReadyEvaluationAt)
        return fields
    }

    private mutating func resetSettleEvidence() {
        settleFirstCheckAfterDeadlineAt = nil
        settleDeadlineOvershootMilliseconds = nil
        settleReadyEvaluationAt = nil
    }
}
