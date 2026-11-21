import XCTest
@testable import bili

final class PlayerSpeedBoostPolicyTests: XCTestCase {
    func testRejectsTerminatedPlayback() {
        XCTAssertEqual(
            PlayerSpeedBoostPolicy.rejectionReason(
                isTerminated: true,
                isLiveStream: false,
                isPlaying: true,
                currentRate: .x10
            ),
            .terminated
        )
    }

    func testRejectsLivePlayback() {
        XCTAssertEqual(
            PlayerSpeedBoostPolicy.rejectionReason(
                isTerminated: false,
                isLiveStream: true,
                isPlaying: true,
                currentRate: .x10
            ),
            .live
        )
    }

    func testRejectsPausedPlayback() {
        XCTAssertEqual(
            PlayerSpeedBoostPolicy.rejectionReason(
                isTerminated: false,
                isLiveStream: false,
                isPlaying: false,
                currentRate: .x10
            ),
            .paused
        )
    }

    func testRejectsWhenAlreadyAtTwoTimesSpeed() {
        XCTAssertEqual(
            PlayerSpeedBoostPolicy.rejectionReason(
                isTerminated: false,
                isLiveStream: false,
                isPlaying: true,
                currentRate: .x20
            ),
            .alreadyAtMaximumRate
        )
    }

    func testAllowsPlayingVideoOnARegularRate() {
        XCTAssertNil(
            PlayerSpeedBoostPolicy.rejectionReason(
                isTerminated: false,
                isLiveStream: false,
                isPlaying: true,
                currentRate: .x15
            )
        )
    }

    @MainActor
    func testPlayerReplacementRestoresThePlayerThatStartedSpeedBoost() {
        let playerA = PlayerStateViewModel(
            videoURL: nil,
            audioURL: nil,
            title: "Player A",
            referer: "https://www.bilibili.com"
        )
        let playerB = PlayerStateViewModel(
            videoURL: nil,
            audioURL: nil,
            title: "Player B",
            referer: "https://www.bilibili.com"
        )
        defer {
            playerA.stop()
            playerB.stop()
        }

        playerA.setPlaybackRate(.x15)
        playerB.setPlaybackRate(.x075)
        let model = PlayerSpeedBoostModel()
        XCTAssertTrue(
            model.beginIfNeeded(
                playerViewModel: playerA,
                isSurfacePlaying: true,
                hidePlaybackControls: {}
            )
        )
        XCTAssertEqual(playerA.playbackRate, .x20)

        var didShowControls = false
        model.end(
            reason: .playerChanged,
            playerViewModel: playerB,
            showPlaybackControls: { didShowControls = true }
        )

        XCTAssertEqual(playerA.playbackRate, .x15)
        XCTAssertEqual(playerB.playbackRate, .x075)
        XCTAssertFalse(didShowControls)
    }

    func testEdgeGuardRejectsScreenEdgesAndAllowsInterior() {
        XCTAssertFalse(PlayerSpeedBoostPolicy.allowsGestureStart(at: 8, containerWidth: 390))
        XCTAssertFalse(PlayerSpeedBoostPolicy.allowsGestureStart(at: 382, containerWidth: 390))
        XCTAssertTrue(PlayerSpeedBoostPolicy.allowsGestureStart(at: 195, containerWidth: 390))
    }

    func testHorizontalSlideResolvesMultiTierSpeedsWithHysteresis() {
        // Default 1.0x baseline unlocks [1.25, 1.5, 2.0] starting at 1.5x
        var current = 1.5
        current = PlayerSpeedBoostPolicy.resolvedBoostRate(forHorizontalOffset: -60, baselineRate: .x10, currentRate: current)
        XCTAssertEqual(current, 1.25)

        // Near -48pt boundary within hysteresis margin (-48 ..< -40) stays at 1.25
        current = PlayerSpeedBoostPolicy.resolvedBoostRate(forHorizontalOffset: -42, baselineRate: .x10, currentRate: current)
        XCTAssertEqual(current, 1.25)

        current = PlayerSpeedBoostPolicy.resolvedBoostRate(forHorizontalOffset: 0, baselineRate: .x10, currentRate: current)
        XCTAssertEqual(current, 1.5)

        current = PlayerSpeedBoostPolicy.resolvedBoostRate(forHorizontalOffset: 60, baselineRate: .x10, currentRate: current)
        XCTAssertEqual(current, 2.0)

        // Baseline 1.5x starts at 2.0x and clamps at 2.0x
        let from15 = PlayerSpeedBoostPolicy.resolvedBoostRate(forHorizontalOffset: -80, baselineRate: .x15, currentRate: 2.0)
        XCTAssertEqual(from15, 2.0)
    }

    @MainActor
    func testSlideUpToLockPreservesBoostAndUnlockRestoresOriginalRate() {
        let player = PlayerStateViewModel(
            videoURL: nil,
            audioURL: nil,
            title: "Speed Lock Probe",
            referer: "https://www.bilibili.com"
        )
        defer { player.stop() }
        player.setPlaybackRate(.x10)

        let model = PlayerSpeedBoostModel()
        XCTAssertTrue(
            model.beginIfNeeded(
                playerViewModel: player,
                isSurfacePlaying: true,
                hidePlaybackControls: {}
            )
        )
        XCTAssertEqual(model.phase, .boosting)
        XCTAssertEqual(model.displayedRateTitle, "1.5x")

        // Slide right to 2x and slide up past lock threshold (-52pt)
        model.updateGestureOffset(horizontalOffset: 60, verticalOffset: -60, playerViewModel: player)
        XCTAssertEqual(model.displayedRateValue, 2.0)
        XCTAssertEqual(model.displayedRateTitle, "2x")
        XCTAssertTrue(model.isLockTargetHighlighted)

        // Release finger -> enters .locked without restoring 1.0x yet
        model.end(reason: .gestureEnded, playerViewModel: player, showPlaybackControls: {})
        XCTAssertEqual(model.phase, .locked)
        XCTAssertTrue(model.isIndicatorVisible)

        // Seeking while locked preserves locked state
        model.end(reason: .supersededBySeek, playerViewModel: player, showPlaybackControls: {})
        XCTAssertEqual(model.phase, .locked)

        // Tapping locked pill restores exact baseline (1.0x) without waking playback controls
        var didShowControls = false
        model.unlock(playerViewModel: player) {
            didShowControls = true
        }
        XCTAssertEqual(model.phase, .restoring)
        XCTAssertEqual(player.playbackRate, .x10)
        XCTAssertFalse(didShowControls)

        // Normal long-press release also keeps playback controls hidden
        XCTAssertTrue(
            model.beginIfNeeded(
                playerViewModel: player,
                isSurfacePlaying: true,
                hidePlaybackControls: {}
            )
        )
        model.end(reason: .gestureEnded, playerViewModel: player) {
            didShowControls = true
        }
        XCTAssertEqual(player.playbackRate, .x10)
        XCTAssertFalse(didShowControls)
    }
}
