import XCTest
@testable import bili

@MainActor
final class PlaybackRecoveryTestRunnerTests: XCTestCase {
    func testFullScriptRunsAllThirtyThreeTrialsAndKeepsAllThreePauseDurations() async throws {
        let (runner, driver, clock, _) = makeRunner()
        runner.start()
        await finish(runner)
        let report = try XCTUnwrap(runner.report)
        XCTAssertEqual(report.status, "completed")
        XCTAssertEqual(report.trials.count, 33)
        XCTAssertEqual(report.trials.filter { $0.outcome == "observed" }.count, 33)
        XCTAssertEqual(report.schemaVersion, 4)
        for seconds in [5.0, 30, 120] {
            let trials = report.trials.filter { $0.requestedPauseSeconds == seconds }
            XCTAssertEqual(trials.count, 3)
            XCTAssertTrue(trials.allSatisfy { ($0.actualPauseMilliseconds ?? -1) >= seconds * 1_000 - 0.001 })
        }
        XCTAssertGreaterThanOrEqual(clock.time, 465)
        XCTAssertFalse(driver.active)
        XCTAssertFalse(driver.observation.isPlaying)
        XCTAssertFalse(report.exportText.contains("source-secret"))
        XCTAssertTrue(report.trials.allSatisfy { !$0.metrics.isEmpty })
    }

    func testUnknownAndMissingFrameEvidenceNeverBecomesZeroLatencyOrObserved() async throws {
        let (runner, driver, _, _) = makeRunner(repetitions: 1)
        driver.omitResumeFrames = true
        runner.start()
        await finish(runner)
        let trials = try XCTUnwrap(runner.report).trials.filter { $0.requestedPauseSeconds != nil }
        XCTAssertEqual(trials.count, 3)
        XCTAssertTrue(trials.allSatisfy { $0.outcome == "timeout" })
        XCTAssertTrue(trials.allSatisfy { !$0.metrics.contains { $0.fields["playToFrame"] != nil } })
    }

    func testContinuousSeekRequiresFinalTargetNotEarlierRecoveredTargets() async throws {
        let (runner, driver, _, _) = makeRunner(repetitions: 1)
        driver.omitFinalContinuousRecovery = true
        runner.start()
        await finish(runner)
        let last = try XCTUnwrap(runner.report?.trials.first { $0.scenario == .continuousSeek })
        XCTAssertEqual(last.scenario, .continuousSeek)
        XCTAssertEqual(last.targetProgresses, [0.4, 0.75, 0.3])
        XCTAssertEqual(last.outcome, "timeout")
        XCTAssertTrue(last.metrics.contains { $0.kind == "seekRecovery" && $0.fields["requestedTargetSeconds"] == "240.000" })
    }

    func testPausedSeekKeepsPausedThenResumesThroughExplicitPlayCommand() async throws {
        let (runner, _, _, _) = makeRunner(repetitions: 1)
        runner.start()
        await finish(runner)
        let trial = try XCTUnwrap(runner.report?.trials.first { $0.scenario == .pausedSeek })
        XCTAssertEqual(trial.checks["keptPaused"], true)
        XCTAssertEqual(trial.checks["progressAdvancedAfterPlayCommand"], true)
        XCTAssertEqual(trial.outcome, "observed")
    }

    func testUnexpectedPlaybackDuringPausedSeekStopsAndRetainsFailure() async throws {
        let (runner, driver, _, _) = makeRunner(repetitions: 1)
        driver.autoplayPausedSeek = true
        runner.start()
        await finish(runner)
        XCTAssertEqual(runner.report?.status, "failed")
        XCTAssertEqual(runner.report?.trials.last?.checks["keptPaused"], false)
        XCTAssertEqual(runner.report?.trials.last?.outcome, "failed")
        XCTAssertFalse(driver.active)
    }

    func testUserStopCannotBeFollowedByAnOldResumeCommand() async throws {
        let (runner, driver, clock, _) = makeRunner(repetitions: 1)
        var commandsAtStop: Int?
        clock.onSleep = {
            if runner.report?.trials.last?.scenario == .pause5 {
                runner.cancel()
                commandsAtStop = driver.commands.count
                clock.onSleep = nil
            }
        }
        runner.start()
        await finish(runner)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(runner.report?.status, "interrupted")
        XCTAssertEqual(driver.commands.count, commandsAtStop)
        XCTAssertFalse(driver.active)
        XCTAssertFalse(driver.observation.isPlaying)
    }

    func testSystemInterruptionStopsBeforeAnotherSeekOrResume() async throws {
        let (runner, driver, clock, _) = makeRunner(repetitions: 1)
        var count: Int?
        clock.onSleep = {
            clock.onSleep = nil
            driver.onInterrupt?("App离开前台")
            count = driver.commands.count
        }
        runner.start()
        await finish(runner)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(runner.report?.reason, "App离开前台")
        XCTAssertEqual(driver.commands.count, count)
        XCTAssertFalse(driver.active)
    }

    func testSourceChangeStopsWithoutPausingTheReplacementSource() async throws {
        let (runner, driver, clock, _) = makeRunner(repetitions: 1)
        var pausesAtSwitch = 0
        clock.onSleep = {
            clock.onSleep = nil
            driver.identity = "replacement-source-secret"
            pausesAtSwitch = driver.commands.filter { $0 == "pause" }.count
        }
        runner.start()
        await finish(runner)
        XCTAssertEqual(runner.report?.status, "interrupted")
        XCTAssertEqual(driver.commands.filter { $0 == "pause" }.count, pausesAtSwitch)
    }

    func testNetworkChangeIsAnInterruptionNotAComparableSuccess() async throws {
        let (runner, driver, clock, _) = makeRunner(repetitions: 1)
        clock.onSleep = { clock.onSleep = nil; driver.network = "cellular" }
        runner.start()
        await finish(runner)
        XCTAssertEqual(runner.report?.status, "interrupted")
        XCTAssertTrue(runner.report?.reason?.contains("网络类型") == true)
    }

    func testShortOrUnavailableVideoCannotStartCommands() {
        let (runner, driver, _, _) = makeRunner()
        driver.duration = 120
        runner.start()
        XCTAssertFalse(runner.isRunning)
        XCTAssertTrue(driver.commands.isEmpty)
        driver.duration = 600
        driver.available = false
        runner.start()
        XCTAssertFalse(runner.isRunning)
        XCTAssertTrue(driver.commands.isEmpty)
    }

    func testPreparationTimeoutKeepsAnIncompleteReportAndReleasesActiveLease() async throws {
        let (runner, driver, _, _) = makeRunner(repetitions: 1)
        driver.neverFinishesSeek = true
        runner.start()
        await finish(runner)
        XCTAssertEqual(runner.report?.status, "failed")
        XCTAssertEqual(runner.report?.trials.count, 0)
        XCTAssertFalse(driver.active)
    }

    func testOldRunCallbacksCannotContaminateRestartedRun() async throws {
        let (runner, driver, clock, _) = makeRunner(repetitions: 1)
        runner.start()
        let oldCallback = driver.onMetric
        runner.cancel()
        runner.start()
        clock.onSleep = {
            guard runner.report?.trials.last?.scenario == .pause5 else { return }
            clock.onSleep = nil
            oldCallback?("failure", "token=secret")
        }
        await finish(runner)
        XCTAssertEqual(runner.report?.status, "completed")
        XCTAssertFalse(runner.report?.trials.contains { $0.metrics.contains { $0.kind == "failure" } } ?? true)
    }


    func testPauseCommandWorkIsSeparatedFromTheRequestedHold() async throws {
        let (runner, driver, _, _) = makeRunner(repetitions: 1)
        driver.pauseCommandDelay = 0.75
        runner.start()
        await finish(runner)
        let trial = try XCTUnwrap(runner.report?.trials.first)
        XCTAssertEqual(trial.pauseCommandMilliseconds ?? -1, 750, accuracy: 0.001)
        XCTAssertEqual(trial.pauseHoldMilliseconds ?? -1, 5000, accuracy: 0.001)
        XCTAssertEqual(trial.actualPauseMilliseconds ?? -1, 5750, accuracy: 0.001)
        XCTAssertNotNil(trial.playCommandMilliseconds)
        let burst = try XCTUnwrap(runner.report?.trials.first { $0.scenario == .continuousSeek })
        XCTAssertEqual(burst.seekCommandMilliseconds?.count, 3)
    }

    func testRapidCommandsRetainOrderAndRequireDeactivationOverlapAndFinalIntent() async throws {
        let (runner, _, _, _) = makeRunner(repetitions: 1)
        runner.start()
        await finish(runner)
        let report = try XCTUnwrap(runner.report)
        let immediate = try XCTUnwrap(report.trials.first { $0.scenario == .immediateResume })
        let playing = try XCTUnwrap(report.trials.first { $0.scenario == .rapidTogglePlaying })
        let paused = try XCTUnwrap(report.trials.first { $0.scenario == .rapidTogglePaused })
        XCTAssertEqual(immediate.commands?.map(\.action), ["pause", "play"])
        XCTAssertEqual(playing.commands?.map(\.action), ["pause", "play", "pause", "play"])
        XCTAssertEqual(paused.commands?.map(\.action), ["pause", "play", "pause", "play", "pause"])
        for trial in [immediate, playing, paused] {
            XCTAssertEqual(trial.outcome, "observed")
            XCTAssertEqual(trial.checks["playedDuringDeactivation"], true)
            XCTAssertTrue(trial.commands?.allSatisfy { $0.durationMilliseconds >= 0 } == true)
        }
        XCTAssertEqual(playing.checks["finalPlayRecovered"], true)
        XCTAssertEqual(paused.checks["keptPaused"], true)
    }

    func testEarlierRapidPlayFrameCannotPassTheFinalPlay() async throws {
        let (runner, driver, _, _) = makeRunner(repetitions: 1)
        driver.omitFinalRapidFrame = true
        runner.start()
        await finish(runner)
        let trial = try XCTUnwrap(runner.report?.trials.first { $0.scenario == .rapidTogglePlaying })
        XCTAssertEqual(trial.outcome, "timeout")
        XCTAssertEqual(trial.checks["finalPlayRecovered"], false)
        XCTAssertTrue(trial.metrics.contains { $0.fields["stage"] == "firstAdvancingFrame" })
    }

    func testRapidCommandsWithoutDeactivationOverlapCannotClaimRaceWasExercised() async throws {
        let (runner, driver, _, _) = makeRunner(repetitions: 1)
        driver.exposesDeactivationPending = false
        runner.start()
        await finish(runner)
        let trials = try XCTUnwrap(runner.report).trials.filter { $0.scenario.isRapidToggle }
        XCTAssertEqual(trials.count, 3)
        XCTAssertTrue(trials.allSatisfy { $0.outcome == "missingEvidence" })
        XCTAssertTrue(trials.allSatisfy { $0.checks["playedDuringDeactivation"] == false })
    }

    func testLatePlaybackAfterFinalRapidPauseFailsAndRetainsEvidence() async throws {
        let (runner, driver, clock, _) = makeRunner(repetitions: 1)
        clock.onSleep = {
            if runner.report?.trials.last?.scenario == .rapidTogglePaused,
               runner.report?.trials.last?.commands?.count == 5 {
                clock.onSleep = nil
                driver.forceUnexpectedPlayback()
            }
        }
        runner.start()
        await finish(runner)
        XCTAssertEqual(runner.report?.status, "failed")
        XCTAssertEqual(runner.report?.trials.last?.checks["keptPaused"], false)
    }

    func testIntentOnlyPauseViolationRecordsSeparateFlags() async throws {
        let (runner, driver, clock, _) = makeRunner(repetitions: 1)
        clock.onSleep = {
            if runner.report?.trials.last?.scenario == .rapidTogglePaused,
               runner.report?.trials.last?.commands?.count == 5 {
                clock.onSleep = nil
                driver.forceUnexpectedPlayback(intentOnly: true)
            }
        }
        runner.start()
        await finish(runner)
        let trial = try XCTUnwrap(runner.report?.trials.last)
        XCTAssertEqual(runner.report?.status, "failed")
        XCTAssertEqual(trial.checks["keptPaused"], false)
        XCTAssertEqual(trial.checks["playingAtPauseFailure"], false)
        XCTAssertEqual(trial.checks["wantsPlaybackAtPauseFailure"], true)
    }

    func testPauseBoundaryShortPlanCoversIdlePlayAndPauseWithoutSuspension() async throws {
        let (runner, _, clock, _) = makeRunner()
        runner.start(onlyPauseBoundary: true)
        await finish(runner)
        let report = try XCTUnwrap(runner.report)
        XCTAssertEqual(report.context["testPlan"], "pauseBoundary")
        XCTAssertEqual(report.plannedTrialCount, 3)
        XCTAssertEqual(report.trials.count, 3)
        XCTAssertEqual(report.status, "completed")
        XCTAssertLessThan(clock.time, 60)
        for trial in report.trials {
            XCTAssertEqual(trial.scenario, .deactivatedImmediatePause)
            XCTAssertEqual(trial.outcome, "observed")
            let commands = try XCTUnwrap(trial.commands)
            XCTAssertEqual(commands.map(\.action), ["pause", "play", "pause"])
            XCTAssertEqual(commands[1].audioDeactivationPending, false)
            XCTAssertEqual(commands[2].audioDeactivationPending, false)
            XCTAssertEqual(commands[1].isPlayingAfterCommand, true)
            XCTAssertEqual(commands[1].wantsPlaybackAfterCommand, true)
            XCTAssertEqual(commands[2].startedMilliseconds,
                           commands[1].startedMilliseconds + commands[1].durationMilliseconds,
                           accuracy: 0.001)
            XCTAssertEqual(trial.checks["keptPaused"], true)
        }
    }

    func testPauseBoundaryUnknownDeactivationNeverIssuesBoundaryPlay() async throws {
        let (runner, driver, _, _) = makeRunner(repetitions: 1)
        driver.exposesDeactivationPending = false
        runner.start(onlyPauseBoundary: true)
        await finish(runner)
        let trial = try XCTUnwrap(runner.report?.trials.first)
        XCTAssertEqual(trial.outcome, "missingEvidence")
        XCTAssertEqual(trial.commands?.map(\.action), ["pause"])
    }

    func testPauseBoundaryWithoutActualPlayingCannotClaimCoverage() async throws {
        let (runner, driver, _, _) = makeRunner(repetitions: 1)
        driver.suppressIdlePlay = true
        runner.start(onlyPauseBoundary: true)
        await finish(runner)
        let trial = try XCTUnwrap(runner.report?.trials.first)
        XCTAssertEqual(trial.outcome, "missingEvidence")
        XCTAssertEqual(trial.checks["playingBeforeFinalPause"], false)
        XCTAssertEqual(trial.checks["keptPaused"], true)
    }

    func testPauseBoundaryRejectsLatePlaybackAfterFinalPause() async throws {
        let (runner, driver, clock, _) = makeRunner(repetitions: 1)
        clock.onSleep = {
            if runner.report?.trials.last?.commands?.count == 3 {
                clock.onSleep = nil
                driver.forceUnexpectedPlayback()
            }
        }
        runner.start(onlyPauseBoundary: true)
        await finish(runner)
        let trial = try XCTUnwrap(runner.report?.trials.first)
        XCTAssertEqual(runner.report?.status, "failed")
        XCTAssertEqual(trial.checks["keptPaused"], false)
        XCTAssertEqual(trial.checks["playingAtPauseFailure"], true)
        XCTAssertEqual(trial.checks["wantsPlaybackAtPauseFailure"], true)
    }

    func testPauseBoundaryCancellationDuringDeactivationNeverIssuesObsoletePlay() async throws {
        let (runner, _, clock, _) = makeRunner(repetitions: 1)
        clock.onSleep = {
            if runner.report?.trials.last?.commands?.count == 1 {
                clock.onSleep = nil
                runner.cancel()
            }
        }
        runner.start(onlyPauseBoundary: true)
        await finish(runner)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(runner.report?.status, "interrupted")
        XCTAssertEqual(runner.report?.trials.first?.commands?.map(\.action), ["pause"])
    }

    private func makeRunner(repetitions: Int = 3) -> (
        PlaybackRecoveryTestRunner, RecoveryScriptDriver, RecoveryScriptClock, PlaybackRecoveryTestReportStore
    ) {
        let clock = RecoveryScriptClock()
        let driver = RecoveryScriptDriver(clock: clock)
        clock.driver = driver
        var timing = PlaybackRecoveryTestTiming()
        timing.repetitions = repetitions
        timing.pollSeconds = 1
        timing.settleSeconds = 0.2
        timing.pausedSeekHoldSeconds = 0.2
        timing.preparationTimeout = 2
        timing.recoveryTimeout = 2
        timing.now = { clock.time }
        timing.sleep = { try await clock.sleep($0) }
        let store = PlaybackRecoveryTestReportStore(disk: RecoveryScriptMemoryDisk())
        return (PlaybackRecoveryTestRunner(driver: driver, timing: timing, reports: store), driver, clock, store)
    }

    private func finish(_ runner: PlaybackRecoveryTestRunner) async {
        for _ in 0..<20000 {
            if !runner.isRunning { return }
            await Task.yield()
        }
        XCTFail("Virtual-clock script did not finish")
        runner.cancel()
    }
}

@MainActor
private final class RecoveryScriptClock {
    var time = 0.0
    weak var driver: RecoveryScriptDriver?
    var onSleep: (() -> Void)?

    func sleep(_ seconds: Double) async throws {
        try Task.checkCancellation()
        time += seconds
        driver?.advance()
        onSleep?()
        await Task.yield()
        try Task.checkCancellation()
    }
}

@MainActor
private final class RecoveryScriptDriver: PlaybackRecoveryTestDriving {
    let clock: RecoveryScriptClock
    var onMetric: (@MainActor (String, String) -> Void)?
    var onInterrupt: (@MainActor (String) -> Void)?
    var identity = "original-source-secret"
    var network = "wifi"
    var duration = 600.0
    var available = true
    var active = false
    var suppressIdlePlay = false
    var omitResumeFrames = false
    var omitFinalRapidFrame = false
    var exposesDeactivationPending = true
    var omitFinalContinuousRecovery = false
    var autoplayPausedSeek = false
    var neverFinishesSeek = false
    var pauseCommandDelay = 0.0
    var commands: [String] = []
    private var position = 0.0
    private var playingAt: Double?
    private var wants = false
    private var seeking = false
    private var pauseSample: String?
    private var pausedAt = 0.0
    private var deactivationPendingUntil = 0.0
    private var seekGeneration = 0
    private var events: [(Double, () -> Void)] = []

    init(clock: RecoveryScriptClock) { self.clock = clock }

    var observation: PlaybackRecoveryTestObservation {
        PlaybackRecoveryTestObservation(
            available: available, currentTime: position + (playingAt.map { clock.time - $0 } ?? 0),
            duration: duration, isPlaying: playingAt != nil, wantsPlayback: wants,
            isSeeking: seeking,
            audioDeactivationPending: exposesDeactivationPending ? clock.time < deactivationPendingUntil : nil,
            sourceIdentity: identity, networkClass: network
        )
    }

    var reportContext: [String: String] { ["engine": "unit-test-fake", "build": "test"] }
    func setTestingActive(_ active: Bool) { self.active = active }

    func pause() {
        commands.append("pause")
        position = observation.currentTime
        playingAt = nil
        wants = false
        let id = UUID().uuidString
        pauseSample = id
        pausedAt = clock.time
        onMetric?("manualResume", "stage=paused sampleID=\(id) baselineFrame=\(position)")
        clock.time += pauseCommandDelay
        deactivationPendingUntil = clock.time + 0.5
    }

    func play() {
        commands.append("play")
        guard playingAt == nil else { return }
        if suppressIdlePlay, pauseSample != nil, clock.time >= deactivationPendingUntil {
            wants = true
            return
        }
        playingAt = clock.time
        wants = true
        if let id = pauseSample {
            onMetric?("manualResume", "stage=playRequested sampleID=\(id) pauseToPlay=\((clock.time - pausedAt) * 1000)ms targetLoadedRange=covered loadedAheadSeconds=5.0")
            events.append((clock.time + 0.05, { [weak self] in
                self?.onMetric?("manualResume", "stage=transportPlaying sampleID=\(id) playToTransport=50ms")
            }))
            let isFinalRapidPlay = Array(commands.suffix(4)) == ["pause", "play", "pause", "play"]
            if !omitResumeFrames, !(omitFinalRapidFrame && isFinalRapidPlay) {
                events.append((clock.time + 0.1, { [weak self] in
                    self?.onMetric?("manualResume", "stage=firstAdvancingFrame sampleID=\(id) playToFrame=100ms")
                }))
            }
        }
        pauseSample = nil
    }

    func seek(to progress: Double) {
        commands.append("seek")
        pauseSample = nil
        seekGeneration += 1
        let generation = seekGeneration
        let wasPlaying = playingAt != nil || wants
        seeking = true
        let target = progress * duration
        let id = UUID().uuidString
        let targetText = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), target)
        let mode = wasPlaying ? "seekPlaying" : "seekPaused"
        let fields = "sampleID=\(id) requestedTargetSeconds=\(targetText) mode=\(mode) targetLoadedRange=covered loadedAheadSeconds=10.0"
        events.append((clock.time + 0.2, { [weak self] in
            guard let self, !self.neverFinishesSeek else { return }
            if self.seekGeneration == generation {
                self.position = target
                self.playingAt = wasPlaying || self.autoplayPausedSeek ? self.clock.time : nil
                self.wants = wasPlaying || self.autoplayPausedSeek
                self.seeking = false
            }
            self.onMetric?("seek", "slider-engine total=200ms engine=200ms \(fields)")
            if wasPlaying, !(self.omitFinalContinuousRecovery && abs(progress - 0.3) < 0.001) {
                self.onMetric?("seekRecovery", "slider-engine recovered=true total=200ms \(fields)")
            }
        }))
    }

    func advance() {
        let ready = events.filter { $0.0 <= clock.time }
        events.removeAll { $0.0 <= clock.time }
        for (_, action) in ready { action() }
    }

    func forceUnexpectedPlayback(intentOnly: Bool = false) {
        playingAt = intentOnly ? nil : clock.time
        wants = true
    }
}

nonisolated final class RecoveryScriptMemoryDisk: PlaybackRecoveryTestReportPersistence, @unchecked Sendable {
    private let lock = NSLock()
    private var value: PlaybackRecoveryTestReport?
    private var fails = false
    func read() -> PlaybackRecoveryTestReport? { lock.withLock { value } }
    func write(_ report: PlaybackRecoveryTestReport, revision: UInt64) throws {
        try lock.withLock {
            if fails { throw CocoaError(.fileWriteUnknown) }
            value = report
        }
    }
    func setFailure(_ fails: Bool) async { lock.withLock { self.fails = fails } }
}
