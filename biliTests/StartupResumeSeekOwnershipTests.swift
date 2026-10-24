import XCTest
@testable import bili

@MainActor
final class StartupResumeSeekOwnershipTests: XCTestCase {
    func testInitialHistoryCorrectionStillRetriesBeforeAnyUserSeek() async throws {
        let (player, engine, surface) = makePlayer()
        defer {
            player.stop()
            ActivePlaybackCoordinator.shared.stopActivePlayback()
            withExtendedLifetime(surface) {}
        }

        player.play()
        // Surface activation can reschedule the initial correction on a busy
        // simulator. Wait for the actual seek, with a finite failure bound.
        for _ in 0..<100 where engine.seekCallCount == 0 {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertGreaterThan(engine.seekCallCount, 0)
        XCTAssertEqual(engine.lastSeekTime, 40)
    }

    func testTapSeekCancelsAnAlreadyScheduledHistoryCorrection() async throws {
        let (player, engine, surface) = makePlayer()
        defer {
            player.stop()
            ActivePlaybackCoordinator.shared.stopActivePlayback()
            withExtendedLifetime(surface) {}
        }

        player.play()
        player.seek(to: 0.1)
        engine.snapshotTime = 6
        try await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(engine.seekCallCount, 0, "History must not override a tap to 6 seconds")
        XCTAssertEqual(player.currentTime, 6, accuracy: 0.001)
    }

    func testManualResumeCannotRearmHistoryCorrectionAfterBackwardSeek() async throws {
        let (player, engine, surface) = makePlayer()
        defer {
            player.stop()
            ActivePlaybackCoordinator.shared.stopActivePlayback()
            withExtendedLifetime(surface) {}
        }

        player.play()
        player.seek(to: 0.1)
        engine.snapshotTime = 6
        player.pause()
        player.playFromUserInteraction()
        try await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertGreaterThanOrEqual(engine.playCallCount, 2)
        XCTAssertEqual(engine.seekCallCount, 0, "Play must keep the user's 6-second position")
        XCTAssertEqual(player.currentTime, 6, accuracy: 0.001)
    }

    func testStepSeekAlsoCancelsPendingHistoryCorrection() async throws {
        let (player, engine, surface) = makePlayer()
        defer {
            player.stop()
            ActivePlaybackCoordinator.shared.stopActivePlayback()
            withExtendedLifetime(surface) {}
        }

        player.play()
        player.seek(by: 6)
        engine.snapshotTime = 6
        try await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(engine.seekCallCount, 0, "Step seeking must also override history")
        XCTAssertEqual(player.currentTime, 6, accuracy: 0.001)
    }

    private func makePlayer() -> (PlayerStateViewModel, PlayerLifecycleEngineSpy, VideoSurfaceContainerView) {
        let coordinator = ActivePlaybackCoordinator.shared
        coordinator.stopActivePlayback()
        let engine = PlayerLifecycleEngineSpy(isPlaying: false)
        engine.snapshotTime = 0
        let player = PlayerStateViewModel(
            videoURL: URL(string: "https://example.com/video.mp4"),
            audioURL: nil,
            title: "Startup history seek ownership",
            referer: "https://www.bilibili.com",
            durationHint: 60,
            resumeTime: 40,
            startupResumePolicy: .immediate,
            engine: engine
        )
        let surface = VideoSurfaceContainerView()
        player.attachSurface(surface, prefersNativePlaybackControls: false)
        coordinator.activate(player)
        player.setPlaybackIntent(true)
        return (player, engine, surface)
    }
}
