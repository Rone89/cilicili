import XCTest
import UIKit
@testable import bili

@MainActor
final class ActivePlaybackCoordinatorTests: XCTestCase {
    func testCancelledNavigationRestoresActivePlayerIntent() {
        let coordinator = ActivePlaybackCoordinator.shared
        coordinator.stopActivePlayback()
        defer { coordinator.stopActivePlayback() }

        let player = PlayerStateViewModel(
            videoURL: nil,
            audioURL: nil,
            title: "导航恢复测试",
            referer: "https://www.bilibili.com"
        )
        let surface = VideoSurfaceContainerView()
        player.attachSurface(surface, prefersNativePlaybackControls: false)
        player.play()

        XCTAssertTrue(coordinator.isActive(player))
        XCTAssertTrue(player.wantsAutoplay)

        coordinator.pauseActivePlaybackForNavigation()

        XCTAssertFalse(player.wantsAutoplay)
        let pendingResumeState = player.pendingNavigationResumeState()
        XCTAssertNotNil(pendingResumeState)
        XCTAssertTrue(pendingResumeState?.shouldResumePlayback == true)
        XCTAssertTrue(coordinator.resumeActivePlaybackAfterCancelledNavigation())
        XCTAssertTrue(coordinator.isActive(player))
        XCTAssertTrue(player.wantsAutoplay)
    }

    func testCancelledNavigationWithoutActivePlayerDoesNothing() {
        let coordinator = ActivePlaybackCoordinator.shared
        coordinator.stopActivePlayback()

        XCTAssertFalse(coordinator.resumeActivePlaybackAfterCancelledNavigation())
    }

    func testGlobalAppBackgroundPauseStopsRecordedVideoByDefault() {
        let coordinator = ActivePlaybackCoordinator.shared
        coordinator.stopActivePlayback()
        defer { coordinator.stopActivePlayback() }

        let engine = PlayerLifecycleEngineSpy(isPlaying: true)
        let player = PlayerStateViewModel(
            videoURL: nil,
            audioURL: nil,
            title: "默认关闭后台播放测试",
            referer: "https://www.bilibili.com",
            engine: engine
        )
        let surface = VideoSurfaceContainerView()
        player.attachSurface(surface, prefersNativePlaybackControls: false)
        coordinator.activate(player)
        player.setPlaybackIntent(true)
        engine.onFirstFrame?(12)

        XCTAssertTrue(coordinator.pauseActivePlaybackForAppBackground())
        XCTAssertFalse(player.wantsAutoplay)
        XCTAssertEqual(engine.backgroundPauseCallCount, 1)
        XCTAssertFalse(player.resumePlaybackAfterAppBackgroundIfNeeded())
    }

    func testGlobalAppBackgroundPauseKeepsRecordedVideoPlayingWhenEnabled() {
        let coordinator = ActivePlaybackCoordinator.shared
        coordinator.stopActivePlayback()
        defer { coordinator.stopActivePlayback() }

        let engine = PlayerLifecycleEngineSpy(isPlaying: true)
        let player = PlayerStateViewModel(
            videoURL: nil,
            audioURL: nil,
            title: "全局后台续播测试",
            referer: "https://www.bilibili.com",
            engine: engine
        )
        let surface = VideoSurfaceContainerView()
        player.attachSurface(surface, prefersNativePlaybackControls: false)
        coordinator.activate(player)
        player.setBackgroundPlaybackEnabled(true)
        player.setPlaybackIntent(true)
        engine.onFirstFrame?(12)

        XCTAssertFalse(coordinator.pauseActivePlaybackForAppBackground())
        XCTAssertTrue(player.wantsAutoplay)
        XCTAssertEqual(engine.backgroundPauseCallCount, 0)
        XCTAssertFalse(player.resumePlaybackAfterAppBackgroundIfNeeded())
        XCTAssertFalse(player.prepareStoppedPlaybackAfterAppBackgroundIfNeeded())
        XCTAssertEqual(engine.videoOutputRefreshCallCount, 0)
        XCTAssertEqual(engine.pausedPlaybackWarmCallCount, 0)
        XCTAssertEqual(engine.playerItemRecoveryCallCount, 0)
    }

    func testAppDelegateBackgroundCallbacksKeepRecordedVideoPlayingWhenEnabled() {
        let coordinator = ActivePlaybackCoordinator.shared
        coordinator.stopActivePlayback()
        defer { coordinator.stopActivePlayback() }

        let engine = PlayerLifecycleEngineSpy(isPlaying: true)
        let player = PlayerStateViewModel(
            videoURL: nil,
            audioURL: nil,
            title: "应用代理后台续播测试",
            referer: "https://www.bilibili.com",
            engine: engine
        )
        let surface = VideoSurfaceContainerView()
        player.attachSurface(surface, prefersNativePlaybackControls: false)
        coordinator.activate(player)
        player.setBackgroundPlaybackEnabled(true)
        player.setPlaybackIntent(true)

        let appDelegate = AppDelegate()
        appDelegate.applicationDidEnterBackground(UIApplication.shared)
        appDelegate.applicationProtectedDataWillBecomeUnavailable(UIApplication.shared)

        XCTAssertEqual(engine.backgroundPauseCallCount, 0)
        XCTAssertTrue(player.wantsAutoplay)
    }
}
