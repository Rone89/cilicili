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

    func testScreenLockPausesActivePictureInPictureWhenBackgroundPlaybackDisabled() {
        let coordinator = ActivePlaybackCoordinator.shared
        coordinator.stopActivePlayback()
        defer { coordinator.stopActivePlayback() }

        let engine = PlayerLifecycleEngineSpy(isPlaying: true)
        engine.supportsPictureInPicture = true
        engine.isPictureInPictureActive = true
        let player = PlayerStateViewModel(
            videoURL: nil,
            audioURL: nil,
            title: "锁屏暂停画中画测试",
            referer: "https://www.bilibili.com",
            engine: engine
        )
        let surface = VideoSurfaceContainerView()
        player.attachSurface(surface, prefersNativePlaybackControls: false)
        coordinator.activate(player)
        player.setPictureInPictureEnabled(true)
        player.setBackgroundPlaybackEnabled(false)
        player.setPlaybackIntent(true)
        engine.onFirstFrame?(12)

        let appDelegate = AppDelegate()
        // Normal backgrounding keeps active PiP playing on the Home Screen.
        appDelegate.applicationDidEnterBackground(UIApplication.shared)
        XCTAssertEqual(engine.backgroundPauseCallCount, 0)
        XCTAssertTrue(player.wantsAutoplay)

        // Device lock pauses active PiP unless background playback is enabled.
        appDelegate.applicationProtectedDataWillBecomeUnavailable(UIApplication.shared)
        XCTAssertEqual(engine.backgroundPauseCallCount, 1)
        XCTAssertFalse(player.wantsAutoplay)
    }

    func testAppDelegateSceneLifecycleFilteringIgnoresSecondaryAndMismatchedScenes() {
        XCTAssertFalse(
            AppDelegate.shouldPauseActivePlaybackForSceneDidEnterBackground(
                AppDelegate.SceneLifecycleEvaluationContext(
                    hasNotificationObject: true,
                    isWindowScene: true,
                    isApplicationWindowScene: false,
                    hasPrimaryAppWindow: false,
                    matchesActivePlayerWindowScene: false,
                    hasActivePlayerWindowScene: true,
                    hasOtherForegroundApplicationScene: true,
                    applicationState: .active
                )
            )
        )
        XCTAssertFalse(
            AppDelegate.shouldPauseActivePlaybackForSceneDidEnterBackground(
                AppDelegate.SceneLifecycleEvaluationContext(
                    hasNotificationObject: true,
                    isWindowScene: true,
                    isApplicationWindowScene: true,
                    hasPrimaryAppWindow: true,
                    matchesActivePlayerWindowScene: false,
                    hasActivePlayerWindowScene: true,
                    hasOtherForegroundApplicationScene: true,
                    applicationState: .active
                )
            )
        )
        XCTAssertFalse(
            AppDelegate.shouldPauseActivePlaybackForSceneDidEnterBackground(
                AppDelegate.SceneLifecycleEvaluationContext(
                    hasNotificationObject: false,
                    isWindowScene: false,
                    isApplicationWindowScene: false,
                    hasPrimaryAppWindow: false,
                    matchesActivePlayerWindowScene: false,
                    hasActivePlayerWindowScene: false,
                    hasOtherForegroundApplicationScene: true,
                    applicationState: .active
                )
            )
        )
        XCTAssertTrue(
            AppDelegate.shouldPauseActivePlaybackForSceneDidEnterBackground(
                AppDelegate.SceneLifecycleEvaluationContext(
                    hasNotificationObject: true,
                    isWindowScene: true,
                    isApplicationWindowScene: true,
                    hasPrimaryAppWindow: true,
                    matchesActivePlayerWindowScene: true,
                    hasActivePlayerWindowScene: true,
                    hasOtherForegroundApplicationScene: false,
                    applicationState: .inactive
                )
            )
        )
        XCTAssertTrue(
            AppDelegate.shouldPauseActivePlaybackForSceneDidEnterBackground(
                AppDelegate.SceneLifecycleEvaluationContext(
                    hasNotificationObject: true,
                    isWindowScene: true,
                    isApplicationWindowScene: true,
                    hasPrimaryAppWindow: true,
                    matchesActivePlayerWindowScene: false,
                    hasActivePlayerWindowScene: false,
                    hasOtherForegroundApplicationScene: false,
                    applicationState: .background
                )
            )
        )
        XCTAssertFalse(
            AppDelegate.shouldRestoreActivePlaybackForSceneWillEnterForeground(
                AppDelegate.SceneLifecycleEvaluationContext(
                    hasNotificationObject: true,
                    isWindowScene: true,
                    isApplicationWindowScene: false,
                    hasPrimaryAppWindow: false,
                    matchesActivePlayerWindowScene: false,
                    hasActivePlayerWindowScene: true,
                    hasOtherForegroundApplicationScene: true,
                    applicationState: .active
                )
            )
        )
        XCTAssertTrue(
            AppDelegate.shouldRestoreActivePlaybackForSceneWillEnterForeground(
                AppDelegate.SceneLifecycleEvaluationContext(
                    hasNotificationObject: true,
                    isWindowScene: true,
                    isApplicationWindowScene: true,
                    hasPrimaryAppWindow: true,
                    matchesActivePlayerWindowScene: true,
                    hasActivePlayerWindowScene: true,
                    hasOtherForegroundApplicationScene: false,
                    applicationState: .active
                )
            )
        )
        XCTAssertFalse(
            BiliPlayerLifecycleHostPolicy.shouldDeliverBackgroundScenePhase(
                applicationState: .active,
                hasForegroundKeyWindow: true
            )
        )
        XCTAssertTrue(
            BiliPlayerLifecycleHostPolicy.shouldDeliverBackgroundScenePhase(
                applicationState: .background,
                hasForegroundKeyWindow: false
            )
        )
    }

    func testAppDelegateSceneBackgroundHandlerIgnoresNonSceneObjectForForegroundPlayer() {
        let coordinator = ActivePlaybackCoordinator.shared
        coordinator.stopActivePlayback()
        defer { coordinator.stopActivePlayback() }

        let engine = PlayerLifecycleEngineSpy(isPlaying: true)
        let player = PlayerStateViewModel(
            videoURL: nil,
            audioURL: nil,
            title: "非场景通知过滤测试",
            referer: "https://www.bilibili.com",
            engine: engine
        )
        let surface = VideoSurfaceContainerView()
        player.attachSurface(surface, prefersNativePlaybackControls: false)
        coordinator.activate(player)
        player.setPlaybackIntent(true)
        engine.onFirstFrame?(8)

        let appDelegate = AppDelegate()
        XCTAssertFalse(
            appDelegate.handleSceneDidEnterBackground(
                Notification(name: UIScene.didEnterBackgroundNotification, object: NSObject())
            )
        )
        XCTAssertTrue(player.wantsAutoplay)
        XCTAssertEqual(engine.backgroundPauseCallCount, 0)
        XCTAssertFalse(player.isAwaitingAppBackgroundSurfaceRecovery)
    }
}
