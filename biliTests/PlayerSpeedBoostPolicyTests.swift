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
        // Default 1.0x baseline unlocks [1.5, 2.0, 3.0, 4.0]
        var current = 2.0
        current = PlayerSpeedBoostPolicy.resolvedBoostRate(forHorizontalOffset: -60, baselineRate: .x10, currentRate: current)
        XCTAssertEqual(current, 1.5)

        // Near boundary within hysteresis margin stays at 1.5
        current = PlayerSpeedBoostPolicy.resolvedBoostRate(forHorizontalOffset: -10, baselineRate: .x10, currentRate: current)
        XCTAssertEqual(current, 1.5)

        current = PlayerSpeedBoostPolicy.resolvedBoostRate(forHorizontalOffset: 58, baselineRate: .x10, currentRate: current)
        XCTAssertEqual(current, 3.0)

        current = PlayerSpeedBoostPolicy.resolvedBoostRate(forHorizontalOffset: 120, baselineRate: .x10, currentRate: current)
        XCTAssertEqual(current, 4.0)

        // Baseline 1.5x skips 1.5x tier and clamps at 2.0x on left swipe
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
        player.setPlaybackRate(.x125)

        let model = PlayerSpeedBoostModel()
        XCTAssertTrue(
            model.beginIfNeeded(
                playerViewModel: player,
                isSurfacePlaying: true,
                hidePlaybackControls: {}
            )
        )
        XCTAssertEqual(model.phase, .boosting)
        XCTAssertEqual(model.displayedRateTitle, "2x")

        // Slide right to 3x and slide up past lock threshold (-52pt)
        model.updateGestureOffset(horizontalOffset: 60, verticalOffset: -60, playerViewModel: player)
        XCTAssertEqual(model.displayedRateValue, 3.0)
        XCTAssertEqual(model.displayedRateTitle, "3x")
        XCTAssertTrue(model.isLockTargetHighlighted)

        // Release finger -> enters .locked without restoring 1.25x yet
        model.end(reason: .gestureEnded, playerViewModel: player, showPlaybackControls: {})
        XCTAssertEqual(model.phase, .locked)
        XCTAssertTrue(model.isIndicatorVisible)

        // Seeking while locked preserves locked state
        model.end(reason: .supersededBySeek, playerViewModel: player, showPlaybackControls: {})
        XCTAssertEqual(model.phase, .locked)

        // Tapping locked pill restores exact baseline (1.25x)
        var didShowControls = false
        model.unlock(playerViewModel: player) {
            didShowControls = true
        }
        XCTAssertEqual(model.phase, .restoring)
        XCTAssertEqual(player.playbackRate, .x125)
        XCTAssertTrue(didShowControls)
    }
}
