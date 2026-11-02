import Combine
import Foundation

@MainActor
final class PlaybackRecoveryTestRunner: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var progressText = "尚未开始"
    @Published private(set) var secondsRemaining = 0
    @Published private(set) var report: PlaybackRecoveryTestReport?

    private let driver: any PlaybackRecoveryTestDriving
    private let timing: PlaybackRecoveryTestTiming
    private let reports: PlaybackRecoveryTestReportStore
    private var task: Task<Void, Never>?
    private var generation = 0
    private var trialStartedAt: Double?
    private var sourceIdentity = ""
    private var networkClass = ""

    init(
        driver: any PlaybackRecoveryTestDriving,
        timing: PlaybackRecoveryTestTiming = PlaybackRecoveryTestTiming(),
        reports: PlaybackRecoveryTestReportStore = .shared
    ) {
        self.driver = driver
        self.timing = timing
        self.reports = reports
    }

    var readinessMessage: String? {
        let value = driver.observation
        if let issue = value.issue { return issue }
        guard value.available else { return "请先让视频开始播放，再打开测试页。" }
        guard value.duration.isFinite, value.duration >= 300 else {
            return "请选择至少5分钟的普通视频。"
        }
        return nil
    }

    func start(onlyPauseBoundary: Bool = false) {
        guard !isRunning, readinessMessage == nil else { return }
        generation &+= 1
        let token = generation
        let snapshot = driver.observation
        sourceIdentity = snapshot.sourceIdentity
        networkClass = snapshot.networkClass
        let scenarios: [PlaybackRecoveryTestScenario] = onlyPauseBoundary
            ? [.deactivatedImmediatePause] : PlaybackRecoveryTestScenario.allCases
        var context = driver.reportContext
        context["testPlan"] = onlyPauseBoundary ? "pauseBoundary" : "full"
        report = PlaybackRecoveryTestReport(
            context: context,
            plannedTrialCount: scenarios.count * timing.repetitions
        )
        guard let report else { return }
        reports.begin(report)
        isRunning = true
        progressText = "准备测试"
        driver.onMetric = { [weak self] kind, message in
            guard let self, self.generation == token else { return }
            self.record(kind: kind, message: message)
        }
        driver.onInterrupt = { [weak self] reason in
            guard let self, self.generation == token else { return }
            self.cancel(reason: reason)
        }
        driver.setTestingActive(true)
        task = Task { @MainActor [weak self] in
            await self?.execute(scenarios: scenarios, generation: token)
        }
    }

    func cancel(reason: String = "用户停止", pausePlayback: Bool = true) {
        guard isRunning else { return }
        generation &+= 1
        task?.cancel()
        task = nil
        finish(status: "interrupted", reason: reason, pausePlayback: pausePlayback)
    }

    private func execute(scenarios: [PlaybackRecoveryTestScenario], generation token: Int) async {
        do {
            for scenario in scenarios {
                for repetition in 1...timing.repetitions {
                    try check(token)
                    progressText = "\(scenario.title) · 第\(repetition)/\(timing.repetitions)次 · 准备"
                    trialStartedAt = nil
                    try await prepare(scenario: scenario, token: token)
                    try check(token)
                    let trial = PlaybackRecoveryTestTrial(id: UUID(), scenario: scenario, repetition: repetition)
                    report?.trials.append(trial)
                    trialStartedAt = timing.now()
                    checkpoint()
                    progressText = "\(scenario.title) · 第\(repetition)/\(timing.repetitions)次"
                    if let pause = scenario.pauseSeconds {
                        try await pauseTrial(seconds: pause, token: token)
                    } else if scenario == .deactivatedImmediatePause {
                        try await deactivatedImmediatePauseTrial(token: token)
                    } else if scenario.isRapidToggle {
                        try await rapidToggleTrial(scenario: scenario, token: token)
                    } else {
                        try await seekTrial(scenario: scenario, repetition: repetition, token: token)
                    }
                    try check(token)
                    trialStartedAt = nil
                    checkpoint()
                }
            }
            finish(status: "completed", reason: nil, pausePlayback: true)
        } catch is CancellationError {
            // cancel() has already finalized and invalidated this task.
        } catch let error as TestError {
            guard token == generation, isRunning else { return }
            finish(status: error.isInterruption ? "interrupted" : "failed",
                   reason: error.message, pausePlayback: true)
        } catch {
            guard token == generation, isRunning else { return }
            finish(status: "failed", reason: "测试执行异常", pausePlayback: true)
        }
    }

    private func prepare(scenario: PlaybackRecoveryTestScenario, token: Int) async throws {
        let base = scenario == .nearbySeek ? 0.35 : 0.2
        driver.play()
        try check(token)
        driver.seek(to: base)
        let ready = try await wait(seconds: timing.preparationTimeout, token: token) {
            let value = self.driver.observation
            return value.isPlaying && !value.isSeeking && !value.isBuffering
        }
        guard ready else { throw TestError(message: "准备阶段未能恢复播放", isInterruption: false) }
        try await delay(timing.settleSeconds, token: token)
    }

    private func pauseTrial(seconds: Double, token: Int) async throws {
        updateTrial { $0.requestedPauseSeconds = seconds }
        let pausedAt = timing.now()
        driver.pause()
        try check(token)
        let pauseReturnedAt = timing.now()
        updateTrial { $0.pauseCommandMilliseconds = max(0, (pauseReturnedAt - pausedAt) * 1_000) }
        try await delay(seconds, token: token, requiresPaused: true)
        let playRequestedAt = timing.now()
        updateTrial {
            $0.actualPauseMilliseconds = max(0, (playRequestedAt - pausedAt) * 1_000)
            $0.pauseHoldMilliseconds = max(0, (playRequestedAt - pauseReturnedAt) * 1_000)
        }
        driver.play()
        try check(token)
        updateTrial { $0.playCommandMilliseconds = max(0, (timing.now() - playRequestedAt) * 1_000) }
        let found = try await wait(seconds: timing.recoveryTimeout, token: token) {
            self.hasResumeFrame || self.hasFrameObservationTimeout
        }
        if hasResumeFrame {
            completeTrial("observed")
        } else {
            completeTrial(found ? "missingEvidence" : "timeout",
                          reason: "未采集到本次恢复后的前进视频时间戳；不能记为0毫秒或成功")
        }
        try await delay(timing.settleSeconds, token: token)
    }

    private func seekTrial(
        scenario: PlaybackRecoveryTestScenario, repetition: Int, token: Int
    ) async throws {
        let duration = driver.observation.duration
        let targets: [Double]
        switch scenario {
        case .nearbySeek:
            let direction = repetition.isMultiple(of: 2) ? -1.0 : 1.0
            targets = [min(max((driver.observation.currentTime + direction * 12) / duration, 0.1), 0.85)]
        case .distantSeek: targets = [repetition.isMultiple(of: 2) ? 0.8 : 0.7]
        case .pausedSeek: targets = [0.55]
        case .continuousSeek: targets = [0.4, 0.75, 0.3]
        default: targets = []
        }
        updateTrial { $0.targetProgresses = targets }
        if scenario == .pausedSeek {
            let startedAt = timing.now()
            driver.pause()
            try check(token)
            updateTrial { $0.pauseCommandMilliseconds = max(0, (timing.now() - startedAt) * 1_000) }
        }
        for (index, target) in targets.enumerated() {
            try check(token)
            let startedAt = timing.now()
            driver.seek(to: target)
            try check(token)
            updateTrial {
                $0.seekCommandMilliseconds = ($0.seekCommandMilliseconds ?? [])
                    + [max(0, (timing.now() - startedAt) * 1_000)]
            }
            if index < targets.count - 1 {
                try await delay(timing.continuousSeekSpacing, token: token)
            }
        }
        guard let target = targets.last else { return }
        let targetSeconds = target * duration
        if scenario == .pausedSeek {
            let completed = try await wait(seconds: timing.recoveryTimeout, token: token) {
                self.hasSeekTransition(targetSeconds: targetSeconds) && !self.driver.observation.isSeeking
            }
            guard completed else {
                completeTrial("timeout", reason: "暂停跳转未取得完成记录")
                return
            }
            let holdStartedAt = timing.now()
            try await delay(timing.pausedSeekHoldSeconds, token: token, requiresPaused: true)
            updateTrial { $0.pauseHoldMilliseconds = max(0, (timing.now() - holdStartedAt) * 1_000) }
            updateTrial { $0.checks["keptPaused"] = true }
            let baseline = driver.observation.currentTime
            let playStartedAt = timing.now()
            driver.play()
            try check(token)
            updateTrial { $0.playCommandMilliseconds = max(0, (timing.now() - playStartedAt) * 1_000) }
            let resumed = try await wait(seconds: timing.recoveryTimeout, token: token) {
                let value = self.driver.observation
                return value.isPlaying && !value.isSeeking && value.currentTime > baseline + 0.2
            }
            updateTrial { $0.checks["progressAdvancedAfterPlayCommand"] = resumed }
            completeTrial(resumed ? "observed" : "missingEvidence",
                          reason: resumed ? nil : "恢复后未观察到播放进度前进")
        } else {
            let recovered = try await wait(seconds: timing.recoveryTimeout, token: token) {
                self.hasSeekRecovery(targetSeconds: targetSeconds)
                    && !self.driver.observation.isSeeking
            }
            completeTrial(recovered ? "observed" : "timeout",
                          reason: recovered ? nil : "最后目标未在采样窗口取得恢复记录")
        }
        try await delay(timing.settleSeconds, token: token)
    }

    private var metrics: [PlaybackRecoveryTestMetric] { report?.trials.last?.metrics ?? [] }

    private func rapidToggleTrial(scenario: PlaybackRecoveryTestScenario, token: Int) async throws {
        let actions: [String]
        switch scenario {
        case .immediateResume: actions = ["pause", "play"]
        case .rapidTogglePlaying: actions = ["pause", "play", "pause", "play"]
        default: actions = ["pause", "play", "pause", "play", "pause"]
        }
        var finalPlayMetricIndex = 0
        var playedDuringDeactivation = false
        for (index, action) in actions.enumerated() {
            if index > 0, scenario != .immediateResume {
                // Let the submitted worker start without waiting for it to finish.
                try await delay(0.02, token: token)
            }
            if action == "play" { finalPlayMetricIndex = metrics.count }
            let command = try issueCommand(action, token: token)
            if action == "play" {
                playedDuringDeactivation = playedDuringDeactivation || command.audioDeactivationPending == true
            }
        }
        updateTrial { $0.checks["playedDuringDeactivation"] = playedDuringDeactivation }
        if scenario == .rapidTogglePaused {
            let idle = try await wait(seconds: timing.recoveryTimeout, token: token) {
                let value = self.driver.observation
                return value.audioDeactivationPending == false
                    || value.isPlaying || value.wantsPlayback
            }
            try await delay(timing.rapidPausedHoldSeconds, token: token, requiresPaused: true)
            updateTrial { $0.checks["keptPaused"] = true }
            completeTrial(idle && playedDuringDeactivation ? "observed" : "missingEvidence",
                          reason: idle && playedDuringDeactivation ? nil : "未取得音频停用在途及最终停止等待的证据")
        } else {
            let resumed = try await wait(seconds: timing.recoveryTimeout, token: token) {
                let value = self.driver.observation
                return self.hasResumeFrame(since: finalPlayMetricIndex)
                    && value.isPlaying && value.wantsPlayback && !value.isSeeking
            }
            updateTrial { $0.checks["finalPlayRecovered"] = resumed }
            completeTrial(resumed && playedDuringDeactivation ? "observed" : resumed ? "missingEvidence" : "timeout",
                          reason: resumed && playedDuringDeactivation ? nil : "未取得停用在途或最后播放命令的恢复证据")
        }
        try await delay(timing.settleSeconds, token: token)
    }

    private func issueCommand(_ action: String, token: Int) throws -> PlaybackRecoveryTestCommand {
        try check(token)
        let startedAt = timing.now()
        let pending = driver.observation.audioDeactivationPending
        if action == "play" { driver.play() } else { driver.pause() }
        try check(token)
        let after = driver.observation
        let command = PlaybackRecoveryTestCommand(
            action: action,
            startedMilliseconds: max(0, (startedAt - (trialStartedAt ?? startedAt)) * 1_000),
            durationMilliseconds: max(0, (timing.now() - startedAt) * 1_000),
            audioDeactivationPending: pending,
            isPlayingAfterCommand: after.isPlaying,
            wantsPlaybackAfterCommand: after.wantsPlayback
        )
        updateTrial {
            if $0.commands == nil { $0.commands = [] }
            $0.commands?.append(command)
        }
        return command
    }

    private func deactivatedImmediatePauseTrial(token: Int) async throws {
        _ = try issueCommand("pause", token: token)
        let idle = try await wait(seconds: timing.recoveryTimeout, token: token) {
            let value = self.driver.observation
            return value.audioDeactivationPending == false || value.isPlaying || value.wantsPlayback
        }
        try await delay(0, token: token, requiresPaused: true)
        guard idle, driver.observation.audioDeactivationPending == false else {
            completeTrial("missingEvidence", reason: "未确认音频停用结束，没有执行边界播放／暂停")
            return
        }
        // No await between these commands: queued playing callbacks must run
        // after the newer pause, just as in the deterministic AVPlayer regression.
        let play = try issueCommand("play", token: token)
        let pause = try issueCommand("pause", token: token)
        let covered = play.audioDeactivationPending == false
            && pause.audioDeactivationPending == false && play.isPlayingAfterCommand == true
            && play.wantsPlaybackAfterCommand == true
        updateTrial {
            $0.checks["deactivationFinishedBeforePlay"] = play.audioDeactivationPending == false
            $0.checks["deactivationFinishedBeforeFinalPause"] = pause.audioDeactivationPending == false
            $0.checks["playingBeforeFinalPause"] = play.isPlayingAfterCommand == true
            $0.checks["playIntentBeforeFinalPause"] = play.wantsPlaybackAfterCommand == true
        }
        let finished = try await wait(seconds: timing.recoveryTimeout, token: token) {
            let value = self.driver.observation
            return value.audioDeactivationPending == false || value.isPlaying || value.wantsPlayback
        }
        try await delay(timing.rapidPausedHoldSeconds, token: token, requiresPaused: true)
        updateTrial { $0.checks["keptPaused"] = true }
        completeTrial(finished && covered ? "observed" : "missingEvidence",
                      reason: finished && covered ? nil : "未取得停用已结束、实际播放及最后暂停保持的完整边界证据")
        try await delay(timing.settleSeconds, token: token)
    }

    private var hasResumeFrame: Bool { hasResumeFrame(since: 0) }

    private func hasResumeFrame(since index: Int) -> Bool {
        let currentMetrics = metrics.dropFirst(index)
        let ids = Set(currentMetrics.filter {
            $0.kind == "manualResume" && $0.fields["stage"] == "playRequested"
        }.compactMap { $0.fields["sampleID"] })
        return currentMetrics.contains {
            $0.kind == "manualResume" && $0.fields["stage"] == "firstAdvancingFrame"
                && $0.fields["playToFrame"] != nil && $0.fields["playToFrame"] != "-"
                && $0.fields["sampleID"].map(ids.contains) == true
        }
    }

    private var hasFrameObservationTimeout: Bool {
        metrics.contains { $0.kind == "manualResume" && $0.fields["stage"] == "frameObservationTimeout" }
    }

    private func hasSeekTransition(targetSeconds: Double) -> Bool {
        metrics.contains {
            $0.kind == "seek" && matchesTarget($0, targetSeconds)
        }
    }

    private func hasSeekRecovery(targetSeconds: Double) -> Bool {
        let ids = Set(metrics.filter {
            $0.kind == "seek" && matchesTarget($0, targetSeconds)
        }.compactMap { $0.fields["sampleID"] })
        return metrics.contains {
            $0.kind == "seekRecovery" && $0.fields["recovered"] == "true"
                && $0.fields["mode"] == "seekPlaying"
                && $0.fields["total"] != nil && $0.fields["total"] != "-"
                && $0.fields["sampleID"].map(ids.contains) == true
        }
    }

    private func matchesTarget(_ metric: PlaybackRecoveryTestMetric, _ seconds: Double) -> Bool {
        guard let raw = metric.fields["requestedTargetSeconds"], let target = Double(raw), target.isFinite else {
            return false
        }
        return abs(target - seconds) <= 0.01
    }

    private func record(kind: String, message: String) {
        guard isRunning, let start = trialStartedAt,
              let metric = PlaybackRecoveryTestMetric.parse(
                kind: kind, message: message,
                receivedMilliseconds: max(0, (timing.now() - start) * 1_000)
              )
        else { return }
        updateTrial {
            if $0.metrics.count < 32 { $0.metrics.append(metric) }
            else { $0.checks["metricsTruncated"] = true }
        }
        checkpoint()
        if kind == "failure" { cancel(reason: "播放器报告播放失败") }
    }

    private func delay(_ seconds: Double, token: Int, requiresPaused: Bool = false) async throws {
        let deadline = timing.now() + seconds
        while timing.now() < deadline {
            try check(token)
            if requiresPaused {
                let value = driver.observation
                if value.isPlaying || value.wantsPlayback {
                    updateTrial {
                        $0.checks["keptPaused"] = false
                        $0.checks["playingAtPauseFailure"] = value.isPlaying
                        $0.checks["wantsPlaybackAtPauseFailure"] = value.wantsPlayback
                        $0.checks["audioDeactivationPendingAtPauseFailure"] = value.audioDeactivationPending
                    }
                    throw TestError(message: "暂停期间出现播放意图或播放状态", isInterruption: false)
                }
            }
            let remaining = max(0, deadline - timing.now())
            let displayed = Int(ceil(remaining))
            if secondsRemaining != displayed { secondsRemaining = displayed }
            try await timing.sleep(min(timing.pollSeconds, remaining))
        }
        try check(token)
        if requiresPaused {
            let value = driver.observation
            if value.isPlaying || value.wantsPlayback {
                updateTrial {
                    $0.checks["keptPaused"] = false
                    $0.checks["playingAtPauseFailure"] = value.isPlaying
                    $0.checks["wantsPlaybackAtPauseFailure"] = value.wantsPlayback
                    $0.checks["audioDeactivationPendingAtPauseFailure"] = value.audioDeactivationPending
                }
                throw TestError(message: "暂停期间出现播放意图或播放状态", isInterruption: false)
            }
        }
        secondsRemaining = 0
    }

    private func wait(seconds: Double, token: Int, predicate: () -> Bool) async throws -> Bool {
        let deadline = timing.now() + seconds
        while true {
            try check(token)
            if predicate() { return true }
            guard timing.now() < deadline else { return false }
            try await timing.sleep(min(timing.pollSeconds, max(0, deadline - timing.now())))
        }
    }

    private func check(_ token: Int) throws {
        try Task.checkCancellation()
        guard token == generation, isRunning else { throw CancellationError() }
        let value = driver.observation
        if let issue = value.issue { throw TestError(message: issue, isInterruption: true) }
        guard value.sourceIdentity == sourceIdentity else {
            throw TestError(message: "视频源或倍速发生变化", isInterruption: true)
        }
        guard value.networkClass == networkClass else {
            throw TestError(message: "网络类型发生变化，请在稳定网络重新开始", isInterruption: true)
        }
    }

    private func updateTrial(_ update: (inout PlaybackRecoveryTestTrial) -> Void) {
        guard var current = report, !current.trials.isEmpty else { return }
        update(&current.trials[current.trials.count - 1])
        report = current
    }

    private func completeTrial(_ outcome: String, reason: String? = nil) {
        updateTrial { $0.outcome = outcome; $0.reason = reason }
    }

    private func checkpoint() {
        guard let report else { return }
        reports.update(report)
    }

    private func finish(status: String, reason: String?, pausePlayback: Bool) {
        guard isRunning else { return }
        isRunning = false
        secondsRemaining = 0
        trialStartedAt = nil
        if report?.trials.last?.outcome == "running" {
            completeTrial(status, reason: reason)
        }
        report?.status = status
        report?.reason = reason
        report?.endedAt = Date()
        progressText = status == "completed" ? "测试结束" : "测试已停止"
        driver.onMetric = nil
        driver.onInterrupt = nil
        // Do not issue a command to an old player after a navigation/player switch.
        if pausePlayback, driver.observation.issue == nil,
           driver.observation.sourceIdentity == sourceIdentity { driver.pause() }
        driver.setTestingActive(false)
        checkpoint()
        task = nil
    }

    private struct TestError: Error {
        let message: String
        let isInterruption: Bool
    }
}
