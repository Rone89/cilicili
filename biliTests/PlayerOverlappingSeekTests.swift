import XCTest
@testable import bili

@MainActor
final class PlayerOverlappingSeekTests: XCTestCase {
    func testScriptedContinuousCommitsPreservePlayingIntentAndIgnoreOlderCompletions() async throws {
        let (player, engine, surface, metricsID) = makePlayer(playing: true)
        let requests = HeldInteractiveSeeks()
        engine.interactiveSeekHandler = { await requests.seek(progress: $0, duration: $1) }
        let driver = PlayerRecoveryTestDriver(player: player, metricsID: metricsID)
        defer { requests.finishAll(); player.stop(); _ = surface }
        for (index, progress) in [0.4, 0.75, 0.3].enumerated() {
            driver.seek(to: progress)
            try await wait { requests.count == index + 1 }
            if index == 0 {
                // A queued playing callback must re-pause quietly, without
                // deactivating audio or replacing the saved user intent.
                engine.onPlaybackStateChange?(.playing)
            }
        }
        engine.snapshotTime = 180
        requests.finish(2, result: 180)
        try await wait { engine.playCallCount > 0 }
        XCTAssertTrue(player.wantsAutoplay)
        XCTAssertEqual(player.currentTime, 180, accuracy: 0.01)
        let callsAfterFinal = engine.playCallCount
        requests.finish(1, result: nil)
        requests.finish(0, result: 240)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(player.wantsAutoplay)
        XCTAssertEqual(player.currentTime, 180, accuracy: 0.01)
        XCTAssertEqual(engine.playCallCount, callsAfterFinal)
        XCTAssertEqual(engine.seekCallCount, 0, "A cancelled completion must not fallback to an old target")
        XCTAssertEqual(engine.pauseCallCount, 0, "Interactive commits must not release the audio session")
        XCTAssertGreaterThanOrEqual(engine.scrubPauseCallCount, 6)
        let message = try XCTUnwrap(PlayerPerformanceStore.shared.session(for: metricsID)?.seekMessage)
        XCTAssertTrue(message.contains("mode=seekPlaying"), message)
        XCTAssertFalse(message.contains("mode=seekPaused"), message)
    }

    func testContinuousCommitsStartingPausedStayPaused() async throws {
        let (player, engine, surface, metricsID) = makePlayer(playing: false)
        let requests = HeldInteractiveSeeks()
        engine.interactiveSeekHandler = { await requests.seek(progress: $0, duration: $1) }
        let driver = PlayerRecoveryTestDriver(player: player, metricsID: metricsID)
        defer { requests.finishAll(); player.stop(); _ = surface }
        for (index, progress) in [0.4, 0.75, 0.3].enumerated() {
            driver.seek(to: progress)
            try await wait { requests.count == index + 1 }
        }
        engine.snapshotTime = 180
        requests.finish(2, result: 180)
        try await wait { !player.isUserSeeking }
        requests.finish(0, result: nil)
        requests.finish(1, result: nil)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(player.wantsAutoplay)
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(engine.playCallCount, 0)
        XCTAssertEqual(engine.pauseCallCount, 0)
        let message = try XCTUnwrap(PlayerPerformanceStore.shared.session(for: metricsID)?.seekMessage)
        XCTAssertTrue(message.contains("mode=seekPaused"), message)
    }

    func testExplicitPauseWhileCommitsArePendingWinsOverOriginalPlayingIntent() async throws {
        let (player, engine, surface, metricsID) = makePlayer(playing: true)
        let requests = HeldInteractiveSeeks()
        engine.interactiveSeekHandler = { await requests.seek(progress: $0, duration: $1) }
        let driver = PlayerRecoveryTestDriver(player: player, metricsID: metricsID)
        defer { requests.finishAll(); player.stop(); _ = surface }
        driver.seek(to: 0.4)
        try await wait { requests.count == 1 }
        driver.seek(to: 0.3)
        try await wait { requests.count == 2 }
        player.pause()
        requests.finish(1, result: nil)
        requests.finish(0, result: nil)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(player.wantsAutoplay)
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(engine.playCallCount, 0)
        XCTAssertEqual(engine.pauseCallCount, 1, "An explicit user pause retains its normal audio-session semantics")
        XCTAssertEqual(engine.seekCallCount, 0, "Cancelled requests cannot issue a fallback after explicit pause")
    }

    func testPausedSliderSeekStartsAFreshRecoveryBudgetAtExplicitPlay() async throws {
        try await assertPausedSeekHasNoLateRetry(useSlider: true)
    }

    func testPausedScrubSeekStartsAFreshRecoveryBudgetAtExplicitPlay() async throws {
        try await assertPausedSeekHasNoLateRetry(useSlider: false)
    }


    func testPauseAudioWorkIsCorrelatedAndCannotAttachAfterResume() throws {
        let (player, engine, surface, metricsID) = makePlayer(playing: true)
        defer { player.stop(); _ = surface }
        player.pause()
        player.recordManualPauseAudioDeactivation(milliseconds: 740, succeeded: true)
        player.recordManualPauseAudioDeactivation(milliseconds: .nan, succeeded: false)
        let records = PlayerPerformanceStore.shared.events.filter {
            $0.metricsID == metricsID && $0.message?.contains("stage=audioSessionDeactivation") == true
        }
        XCTAssertEqual(records.count, 1)
        let paused = try XCTUnwrap(PlayerPerformanceStore.shared.events.first {
            $0.metricsID == metricsID && $0.message?.hasPrefix("stage=paused") == true
        }?.message)
        let sampleID = try XCTUnwrap(paused.components(separatedBy: "sampleID=").last)
        XCTAssertTrue(records[0].message?.contains("sampleID=\(sampleID)") == true)
        XCTAssertTrue(records[0].message?.contains("audioDeactivationMs=740.0") == true)
        engine.snapshotTime = 12
        player.playFromUserInteraction()
        player.recordManualPauseAudioDeactivation(milliseconds: 99, succeeded: true)
        XCTAssertEqual(PlayerPerformanceStore.shared.events.filter {
            $0.metricsID == metricsID && $0.message?.contains("stage=audioSessionDeactivation") == true
        }.count, 1)
    }


    func testHealthyPausedSeekResumeResolvesFreshGuardWithoutReseeking() async throws {
        let (player, engine, surface, metricsID) = makePlayer(playing: false)
        defer { player.stop(); _ = surface }
        player.beginUserScrubInteraction()
        player.seekAfterSliderCommit(to: 0.55)
        try await wait { !player.isUserSeeking }
        engine.requiresRenderedVideoTimeForRecovery = true
        engine.snapshotTime = 330.04
        engine.renderedVideoTime = 330.04
        player.playFromUserInteraction()
        try await wait {
            PlayerPerformanceStore.shared.session(for: metricsID)?.seekRecoveryMessage?.contains("recovered=true") == true
        }
        try await Task.sleep(for: .milliseconds(3100))
        XCTAssertEqual(engine.seekCallCount, 0)
        let message = try XCTUnwrap(PlayerPerformanceStore.shared.session(for: metricsID)?.seekRecoveryMessage)
        XCTAssertTrue(message.contains("paused-resume"), message)
    }

    private func assertPausedSeekHasNoLateRetry(useSlider: Bool) async throws {
        let (player, engine, surface, metricsID) = makePlayer(playing: false)
        defer { player.stop(); _ = surface }
        // Keep a deliberately stale rendered/snapshot position. A leftover
        // 2.8-second seek watchdog would interpret this as a stall and reseek.
        engine.snapshotTime = 0
        engine.requiresRenderedVideoTimeForRecovery = true
        engine.renderedVideoTime = nil
        player.beginUserScrubInteraction()
        if useSlider { player.seekAfterSliderCommit(to: 0.55) }
        else { player.seekAfterUserScrub(to: 0.55) }
        try await wait { !player.isUserSeeking }
        try await Task.sleep(for: .milliseconds(2000))
        XCTAssertEqual(engine.seekCallCount, 0)
        XCTAssertNil(PlayerPerformanceStore.shared.session(for: metricsID)?.seekRecoveryMessage)
        player.playFromUserInteraction()
        try await Task.sleep(for: .milliseconds(1100))
        XCTAssertTrue(player.wantsAutoplay)
        XCTAssertEqual(engine.seekCallCount, 0, "The old pre-play deadline must not reseek after only 1.1 seconds of playback")
        // Still-stale video after a fresh full budget must retain recovery.
        try await wait { engine.seekCallCount > 0 }
        let message = try XCTUnwrap(PlayerPerformanceStore.shared.session(for: metricsID)?.seekMessage)
        XCTAssertTrue(message.contains("paused-resume-recovery"), message)
        XCTAssertEqual(engine.pauseCallCount, 0)
        XCTAssertGreaterThanOrEqual(engine.scrubPauseCallCount, 2)
    }

    private func makePlayer(playing: Bool) -> (
        PlayerStateViewModel, PlayerLifecycleEngineSpy, VideoSurfaceContainerView, String
    ) {
        ActivePlaybackCoordinator.shared.stopActivePlayback()
        let engine = PlayerLifecycleEngineSpy(isPlaying: playing)
        engine.snapshotBufferObservationAvailable = true
        let metricsID = UUID().uuidString
        let player = PlayerStateViewModel(
            videoURL: URL(string: "https://unit-test.invalid/video.mp4"), audioURL: nil,
            title: "Overlapping native seeks", referer: "https://www.bilibili.com",
            durationHint: 600, metricsID: metricsID, engine: engine
        )
        let surface = VideoSurfaceContainerView()
        player.attachSurface(surface, prefersNativePlaybackControls: false)
        ActivePlaybackCoordinator.shared.activate(player)
        engine.onFirstFrame?(12)
        player.setPlaybackIntent(playing)
        return (player, engine, surface, metricsID)
    }

    private func wait(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !predicate(), Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(predicate(), "Seek operation did not reach the expected state")
    }
}

@MainActor
private final class HeldInteractiveSeeks {
    private var continuations: [CheckedContinuation<TimeInterval?, Never>?] = []
    var count: Int { continuations.count }

    func seek(progress: Double, duration: TimeInterval?) async -> TimeInterval? {
        await withCheckedContinuation { continuations.append($0) }
    }

    func finish(_ index: Int, result: TimeInterval?) {
        guard continuations.indices.contains(index), let continuation = continuations[index] else { return }
        continuations[index] = nil
        continuation.resume(returning: result)
    }

    func finishAll() {
        for index in continuations.indices { finish(index, result: nil) }
    }
}
