import AVFoundation
import AVKit
import SwiftUI
import XCTest
import UIKit
@testable import bili

final class PlayerFormalPlaybackConfigurationTests: XCTestCase {
    func testTelegramProgressThumbTracksPlaybackPosition() {
        let width: CGFloat = 200
        let diameter: CGFloat = 16

        XCTAssertEqual(
            PlayerNativeProgressSlider.thumbLeadingOffset(
                progress: 0,
                width: width,
                thumbDiameter: diameter
            ),
            0
        )
        XCTAssertEqual(
            PlayerNativeProgressSlider.thumbLeadingOffset(
                progress: 0.5,
                width: width,
                thumbDiameter: diameter
            ),
            92
        )
        XCTAssertEqual(
            PlayerNativeProgressSlider.thumbLeadingOffset(
                progress: 1,
                width: width,
                thumbDiameter: diameter
            ),
            184
        )
    }

    func testLivePlayerControlLayoutOnlyKeepsNavigationActions() {
        XCTAssertFalse(BiliPlayerControlLayout.live.showsProgress)
        XCTAssertFalse(BiliPlayerControlLayout.live.showsPlaybackToggle)
        XCTAssertFalse(BiliPlayerControlLayout.live.showsTimeLabel)

        XCTAssertFalse(BiliPlayerControlLayout.livePiliPod.showsProgress)
        XCTAssertTrue(BiliPlayerControlLayout.livePiliPod.showsPlaybackToggle)
        XCTAssertFalse(BiliPlayerControlLayout.livePiliPod.showsTimeLabel)

        XCTAssertTrue(BiliPlayerControlLayout.standard.showsProgress)
        XCTAssertTrue(BiliPlayerControlLayout.standard.showsPlaybackToggle)
        XCTAssertTrue(BiliPlayerControlLayout.standard.showsTimeLabel)
    }

    func testSystemNowPlayingPublicationIsDisabled() {
        XCTAssertFalse(PlayerSystemMediaPresentationPolicy.publishesNowPlayingInfo)

        let playbackStates = [
            (true, true, false, false, false),
            (true, false, true, false, false),
            (true, false, false, false, false),
            (false, true, true, false, false),
            (true, true, true, true, false),
            (true, true, true, false, true)
        ]
        for state in playbackStates {
            XCTAssertFalse(
                PlayerNowPlayingPublicationPolicy.shouldPublish(
                    isActive: state.0,
                    wantsAutoplay: state.1,
                    isPlaying: state.2,
                    isTerminated: state.3,
                    hasPlaybackFailure: state.4
                )
            )
        }
    }

    func testAudioOnlyPlaybackPublishesNowPlayingWhileActivelyPlaying() {
        XCTAssertTrue(
            PlayerNowPlayingPublicationPolicy.shouldPublish(
                isActive: true,
                wantsAutoplay: true,
                isPlaying: true,
                isTerminated: false,
                hasPlaybackFailure: false,
                playbackContentMode: .audioOnly
            )
        )
        XCTAssertFalse(
            PlayerNowPlayingPublicationPolicy.shouldPublish(
                isActive: false,
                wantsAutoplay: true,
                isPlaying: true,
                isTerminated: false,
                hasPlaybackFailure: false,
                playbackContentMode: .audioOnly
            )
        )
    }

    @MainActor
    func testNowPlayingMetadataUsesVideoAuthorWhenAvailable() {
        let player = PlayerStateViewModel(
            videoURL: nil,
            audioURL: nil,
            title: "播放标题",
            authorName: "  投稿作者  ",
            referer: "https://www.bilibili.com"
        )
        defer { player.stop() }

        XCTAssertEqual(player.nowPlayingArtist, "投稿作者")
    }

    @MainActor
    func testPlayerSettingsRestoresLegacyAV1CodecPreferenceOnlyWhenSupported() {
        let defaults = makeUserDefaults()
        defaults.set("forceAV1", forKey: VideoCodecPreference.storageKey)

        let settings = PlayerSettings(userDefaults: defaults)
        settings.reload()

        let expectedPreference: VideoCodecPreference = PlaybackCodecPolicy.canDecodeAV1 ? .preferAV1 : .auto
        XCTAssertEqual(settings.videoCodecPreference, expectedPreference)
        XCTAssertEqual(defaults.string(forKey: VideoCodecPreference.storageKey), expectedPreference.rawValue)
    }

    @MainActor
    func testLibraryStorePersistsCodecEnablementAndOrder() {
        let defaults = makeUserDefaults()
        let store = LibraryStore(userDefaults: defaults)
        let preference = VideoCodecPreference(codecOrder: [.h264, .hevc])

        store.setVideoCodecPreference(preference)

        XCTAssertEqual(LibraryStore(userDefaults: defaults).videoCodecPreference, preference)
        XCTAssertEqual(defaults.string(forKey: VideoCodecPreference.storageKey), "h264,hevc")
    }

    @MainActor
    func testPlayerSettingsPersistsForceHardwareDecode() {
        let defaults = makeUserDefaults()
        let settings = PlayerSettings(userDefaults: defaults)

        settings.setForceHardwareDecodeEnabled(true)

        XCTAssertTrue(settings.forceHardwareDecodeEnabled)
        XCTAssertTrue(PlaybackHardwareDecodePolicy.stored(in: defaults))
    }

    @MainActor
    func testLibraryStorePersistsVideoCoverDurationBadgeVisibility() {
        let defaults = makeUserDefaults()
        let store = LibraryStore(userDefaults: defaults)

        XCTAssertFalse(store.showsVideoCoverDurationBadges)
        store.setShowsVideoCoverDurationBadges(true)

        XCTAssertTrue(
            LibraryStore(userDefaults: defaults).showsVideoCoverDurationBadges
        )
    }

    @MainActor
    func testLibraryStoreDefaultsVideoDetailAutoplayOnAndPersistsSelection() {
        let defaults = makeUserDefaults()
        let store = LibraryStore(userDefaults: defaults)

        XCTAssertTrue(store.videoDetailAutoplayEnabled)
        store.setVideoDetailAutoplayEnabled(false)

        XCTAssertFalse(
            LibraryStore(userDefaults: defaults).videoDetailAutoplayEnabled
        )
    }

    @MainActor
    func testLibraryStoreRetiresFormerListenAndMetalExperimentFlags() {
        let defaults = makeUserDefaults()
        let retiredKeys = [
            "cc.bili.playback.videoListenModeExperimentEnabled.v1",
            "cc.bili.playback.officialListenerPlaylistExperimentEnabled.v1",
            "cc.bili.playback.metalDanmakuRendererExperimentEnabled.v1",
        ]
        retiredKeys.forEach { defaults.set(false, forKey: $0) }

        _ = LibraryStore(userDefaults: defaults)

        retiredKeys.forEach { XCTAssertNil(defaults.object(forKey: $0)) }
    }

    func testPlayerStreamSourceResumeTimePreservesAudioOnlyMode() {
        let source = PlayerStreamSource(
            metricsID: "audio-only-test",
            videoURL: nil,
            audioURL: URL(string: "https://example.com/audio.m4s"),
            videoStream: nil,
            audioStream: nil,
            alternateVideoRenditions: [],
            referer: "https://www.bilibili.com",
            httpHeaders: [:],
            title: "Test",
            durationHint: 100,
            isLiveStream: false,
            isLiveHLS: false,
            liveHLSFormat: nil,
            resumeTime: 0,
            dynamicRange: .sdr,
            cdnPreference: .automatic,
            playbackContentMode: .audioOnly
        )

        let resumed = source.withResumeTime(42)
        XCTAssertEqual(resumed.resumeTime, 42)
        XCTAssertEqual(resumed.playbackContentMode, .audioOnly)
    }

    @MainActor
    func testLibraryStoreRetiresPromotedVideoAndLiveExperimentPreferences() {
        let defaults = makeUserDefaults()
        let videoSurfaceKey = "cc.bili.videoDetail.directUIKitSurfaceExperimentEnabled.v1"
        let liveLayoutKey = "cc.bili.live.simpleLiveRoomLayoutExperimentEnabled.v1"
        defaults.set(false, forKey: videoSurfaceKey)
        defaults.set(false, forKey: liveLayoutKey)

        _ = LibraryStore(userDefaults: defaults)

        XCTAssertNil(defaults.object(forKey: videoSurfaceKey))
        XCTAssertNil(defaults.object(forKey: liveLayoutKey))
    }

    @MainActor
    func testExplicitPlaybackPromptsDoNotReturnAfterPause() {
        let player = PlayerStateViewModel(
            videoURL: nil,
            audioURL: nil,
            title: "Test",
            referer: "https://www.bilibili.com"
        )
        defer { player.stop() }

        player.setInitialManualPlaybackPrompt(true)
        player.setRelatedVideoReturnPlaybackPrompt(true)
        XCTAssertTrue(player.isAwaitingInitialManualPlayback)
        XCTAssertTrue(player.isAwaitingRelatedVideoReturnPlayback)

        player.play()
        player.pause()

        XCTAssertFalse(player.isAwaitingInitialManualPlayback)
        XCTAssertFalse(player.isAwaitingRelatedVideoReturnPlayback)
    }

    @MainActor
    func testPlayerSurfaceSnapshotIncludesDurationAndExplicitPlaybackPrompt() {
        let player = PlayerStateViewModel(
            videoURL: nil,
            audioURL: nil,
            title: "Test",
            referer: "https://www.bilibili.com"
        )
        defer { player.stop() }

        player.duration = 88
        player.setInitialManualPlaybackPrompt(true)
        let snapshot = PlayerSurfaceSnapshot(viewModel: player)

        XCTAssertEqual(snapshot.duration, 88)
        XCTAssertTrue(snapshot.showsExplicitPlaybackStartControl)
    }

    @MainActor
    func testPlayerSurfaceStateRebindStopsOldPlayerUpdatesAndTracksNewPlayer() async {
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

        playerA.duration = 10
        playerB.duration = 20
        let surfaceState = PlayerSurfaceStateModel(viewModel: playerA)
        surfaceState.bind(viewModel: playerA)
        XCTAssertEqual(surfaceState.duration, 10)

        surfaceState.bind(viewModel: playerB)
        XCTAssertEqual(surfaceState.duration, 20)

        playerA.duration = 30
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(surfaceState.duration, 20)

        playerB.duration = 40
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(surfaceState.duration, 40)
    }

    @MainActor
    func testVideoDetailRuntimeSettingsSnapshotTracksPlayerOverlayInputs() async {
        let defaults = makeUserDefaults()
        let libraryStore = LibraryStore(userDefaults: defaults)
        let runtimeSettings = VideoDetailRuntimeSettingsStore()
        runtimeSettings.bind(libraryStore)

        libraryStore.setPictureInPictureEnabled(true)
        libraryStore.setDefaultPlaybackRate(1.5)
        XCTAssertTrue(libraryStore.setAppTintColorHex("#123456"))
        try? await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertTrue(runtimeSettings.pictureInPictureEnabled)
        XCTAssertEqual(runtimeSettings.defaultPlaybackRate, 1.5)
        XCTAssertEqual(runtimeSettings.snapshot.appTintColorHex, "#123456")
    }

    @MainActor
    func testLibraryStoreDefaultsAppIconPreferenceToSystemAndPersistsSelection() {
        let defaults = makeUserDefaults()
        let store = LibraryStore(userDefaults: defaults)

        XCTAssertEqual(store.appIconPreference, .system)
        store.setAppIconPreference(.dark)

        XCTAssertEqual(
            LibraryStore(userDefaults: defaults).appIconPreference,
            .dark
        )
    }

    @MainActor
    func testLibraryStoreDefaultsFontSizeToSystemAndPersistsManualSelection() {
        let defaults = makeUserDefaults()
        let store = LibraryStore(userDefaults: defaults)

        XCTAssertTrue(store.followsSystemFontSize)
        XCTAssertEqual(store.manualFontSize, .standard)

        store.setFollowsSystemFontSize(false)
        store.setManualFontSize(.extraLarge)

        let restoredStore = LibraryStore(userDefaults: defaults)
        XCTAssertFalse(restoredStore.followsSystemFontSize)
        XCTAssertEqual(restoredStore.manualFontSize, .extraLarge)
        XCTAssertEqual(restoredStore.manualFontSize.contentSizeCategory, .extraExtraLarge)
    }

    @MainActor
    func testAppTypographyScalesSemanticVideoTitleRoles() {
        let regular = AppTypography.Role.feedVideoTitle.uiFont(contentSizeCategory: .large)
        let compact = AppTypography.Role.compactVideoTitle.uiFont(contentSizeCategory: .large)
        let accessibility = AppTypography.Role.feedVideoTitle.uiFont(
            contentSizeCategory: .accessibilityExtraLarge
        )

        XCTAssertEqual(regular.pointSize, 15, accuracy: 0.001)
        XCTAssertEqual(compact.pointSize, 14, accuracy: 0.001)
        XCTAssertGreaterThan(accessibility.pointSize, regular.pointSize)
    }

    @MainActor
    func testLibraryStorePersistsHomeNavigationModeSwitcherExperiment() {
        let defaults = makeUserDefaults()
        let store = LibraryStore(userDefaults: defaults)

        XCTAssertTrue(store.homeNavigationModeSwitcherExperimentEnabled)
        store.setHomeNavigationModeSwitcherExperimentEnabled(false)

        XCTAssertFalse(
            LibraryStore(userDefaults: defaults).homeNavigationModeSwitcherExperimentEnabled
        )
    }

    @MainActor
    func testLibraryStoreRemovesRetiredExperimentPreferences() {
        let defaults = makeUserDefaults()
        let retiredKeys = [
            "cc.bili.playback.startupRequestSchedulingExperimentEnabled.v1",
            "cc.bili.live.videoDetailLayoutExperimentEnabled.v1",
            "cc.bili.live.piliPodLayoutExperimentEnabled.v1",
            "cc.bili.live.parallelStartupExperimentEnabled.v1",
            "cc.bili.live.adaptiveCDNStartupExperimentEnabled.v1",
            "cc.bili.live.slowStartupRouteSwitchExperimentEnabled.v1",
            "cc.bili.live.hlsFastStartExperimentEnabled.v1",
            "cc.bili.live.danmakuRenderBatchingExperimentEnabled.v1",
            "cc.bili.live.rotationSurfaceAlignmentExperimentEnabled.v1",
            "cc.bili.display.mineSingleStackNavigationExperimentEnabled.v1",
            "cc.bili.display.fixedVideoTitleTypographyExperimentEnabled.v1",
            "cc.bili.display.unifiedAppTypographyExperimentEnabled.v1",
            "cc.bili.display.highQualityImageViewerExperimentEnabled.v1",
            "cc.bili.account.messageCenterExperimentEnabled.v1",
            "cc.bili.display.telegramTopEdgeBlurExperimentEnabled.v1",
            "cc.bili.display.uploaderProfileGlassSheetExperimentEnabled.v1",
            "cc.bili.display.uploaderProfileGlassSheetExperimentEnabled.v2",
            "cc.bili.videoDetail.moreControlsSwiftUISheetExperimentEnabled.v1",
            "cc.bili.playback.nativePlayerProgressSliderExperimentEnabled.v1",
            "cc.bili.playback.iosNativePlaybackControlsExperimentEnabled.v1",
            "cc.bili.display.unifiedVideoCoverBorderExperimentEnabled.v1",
            "cc.bili.display.thumbnailLongPressPreviewExperimentEnabled.v1",
            "cc.bili.display.fastScrollImageLoadSuppressionExperimentEnabled.v1",
            "cc.bili.display.remoteImageCDNFailoverExperimentEnabled.v1",
            "cc.bili.home.nativePullRefreshIndicatorExperimentEnabled.v1",
        ]
        retiredKeys.forEach { defaults.set(true, forKey: $0) }

        _ = LibraryStore(userDefaults: defaults)

        retiredKeys.forEach { XCTAssertNil(defaults.object(forKey: $0)) }
    }

    @MainActor
    func testLibraryStoreDefaultsImageDiagnosticsOnAndPersistsToggle() {
        let defaults = makeUserDefaults()
        let store = LibraryStore(userDefaults: defaults)

        XCTAssertTrue(store.remoteImageDiagnosticsEnabled)
        store.setRemoteImageDiagnosticsEnabled(false)

        XCTAssertFalse(
            LibraryStore(userDefaults: defaults).remoteImageDiagnosticsEnabled
        )
    }

    @MainActor
    func testPlaybackSessionTracksActivePlayerIdentityAndDetaches() {
        let player = PlayerStateViewModel(
            videoURL: nil,
            audioURL: nil,
            title: "Playback session test",
            referer: "https://www.bilibili.com"
        )
        let session = PlaybackSession()

        session.replaceActivePlayer(with: player)

        XCTAssertTrue(session.activePlayer === player)
        XCTAssertEqual(session.snapshot.playerID, ObjectIdentifier(player))
        XCTAssertEqual(session.snapshot.phase, .preparing)

        player.isPreparing = false
        player.isPlaying = true
        XCTAssertEqual(session.snapshot.phase, .playing)

        player.isBuffering = true
        XCTAssertEqual(session.snapshot.phase, .buffering)

        player.errorMessage = "Test failure"
        XCTAssertEqual(session.snapshot.phase, .failed)

        session.detach()

        XCTAssertNil(session.activePlayer)
        XCTAssertEqual(session.snapshot, .idle)
        player.stop(reason: .navigation)
    }

    @MainActor
    func testLibraryStoreAllowsHidingSearchRootTab() {
        let defaults = makeUserDefaults()
        let store = LibraryStore(userDefaults: defaults)

        XCTAssertTrue(AppTab.search.canHideFromRootTabBar)
        XCTAssertTrue(AppTab.search.participatesInRootTabVisibilitySettings)

        store.setRootTab(.search, isVisible: false)

        XCTAssertFalse(store.visibleRootTabs.contains(.search))
        XCTAssertFalse(LibraryStore(userDefaults: defaults).visibleRootTabs.contains(.search))
    }

    func testDolbyVisionQualityUsesAutomaticCodecNegotiation() {
        XCTAssertTrue(BiliAPIClient.requiresAutomaticCodecNegotiation(requestedQuality: 125))
        XCTAssertTrue(BiliAPIClient.requiresAutomaticCodecNegotiation(requestedQuality: 126))
        XCTAssertTrue(BiliAPIClient.requiresAutomaticCodecNegotiation(requestedQuality: 129))
        XCTAssertFalse(BiliAPIClient.requiresAutomaticCodecNegotiation(requestedQuality: 120))
    }

    func testHDRPlaybackRecoveryWatchdogAllowsSlowerFirstFrame() {
        XCTAssertLessThan(
            PlaybackRecoveryWatchdogReason.firstFrame.delay(for: .sdr),
            PlaybackRecoveryWatchdogReason.firstFrame.delay(for: .dolbyVision)
        )
        XCTAssertGreaterThanOrEqual(
            PlaybackRecoveryWatchdogReason.firstFrame.delay(for: .dolbyVision),
            11_000_000_000
        )
        XCTAssertLessThan(
            PlaybackRecoveryWatchdogReason.stall.delay(for: .sdr),
            PlaybackRecoveryWatchdogReason.stall.delay(for: .hdr10)
        )
    }

    @MainActor
    func testSystemBackgroundStopsRecordedVideoWhenPictureInPictureIsConfiguredButInactive() {
        let coordinator = ActivePlaybackCoordinator.shared
        coordinator.stopActivePlayback()

        let engine = PlayerLifecycleEngineSpy(isPlaying: true)
        let player = PlayerStateViewModel(
            videoURL: nil,
            audioURL: nil,
            title: "系统后台暂停测试",
            referer: "https://www.bilibili.com",
            engine: engine
        )
        let surface = VideoSurfaceContainerView()
        player.attachSurface(surface, prefersNativePlaybackControls: false)
        coordinator.activate(player)
        player.setPictureInPictureEnabled(true)
        player.setPlaybackIntent(true)
        engine.onFirstFrame?(12)
        defer {
            player.stop()
            coordinator.stopActivePlayback()
        }

        player.pauseForAppBackground()
        XCTAssertFalse(player.wantsAutoplay)
        XCTAssertEqual(engine.backgroundPauseCallCount, 1)
        XCTAssertTrue(player.isAwaitingAppBackgroundSurfaceRecovery)

        // The engine can report a reset time after a long lock. Foreground
        // preparation must still rebuild at the time captured before suspension.
        engine.snapshotTime = 0

        player.pauseForAppBackground()
        XCTAssertEqual(engine.backgroundPauseCallCount, 1)
        XCTAssertFalse(player.resumePlaybackAfterAppBackgroundIfNeeded())
        XCTAssertTrue(player.prepareStoppedPlaybackAfterAppBackgroundIfNeeded())
        XCTAssertFalse(player.wantsAutoplay)
        XCTAssertEqual(engine.recoverSurfaceCallCount, 1)
        XCTAssertEqual(engine.videoOutputRefreshCallCount, 1)
        XCTAssertEqual(engine.seekCallCount, 1)
        XCTAssertEqual(engine.lastSeekTime, 12)
        XCTAssertEqual(engine.pausedPlaybackWarmCallCount, 1)
        XCTAssertEqual(engine.playerItemRecoveryCallCount, 0)
        XCTAssertEqual(engine.playCallCount, 0)

        engine.renderedVideoTime = 12
        XCTAssertTrue(player.isStoppedAppBackgroundSurfaceRecoveryReadyForReveal())
        player.finishAppBackgroundSurfaceRecoveryReveal()
        XCTAssertEqual(player.playbackPhase, .paused)
    }

    @MainActor
    func testForegroundPictureInPictureRecoveryReusesCurrentPlaybackPage() async {
        let engine = PlayerLifecycleEngineSpy(isPlaying: true)
        engine.supportsPictureInPicture = true
        engine.isPictureInPictureActive = true
        let player = PlayerStateViewModel(
            videoURL: nil,
            audioURL: nil,
            title: "画中画返回测试",
            referer: "https://www.bilibili.com",
            engine: engine
        )
        var restoreRequestCount = 0
        player.restoreUserInterfaceForPictureInPictureStop = {
            restoreRequestCount += 1
            return true
        }
        defer { player.stop() }

        let didRestore = await player.restoreInlinePlaybackFromPictureInPictureIfNeeded()

        XCTAssertTrue(didRestore)
        XCTAssertEqual(restoreRequestCount, 0)
        XCTAssertEqual(engine.stopPictureInPictureCallCount, 1)
        XCTAssertFalse(player.isPictureInPictureActive)
    }

    @MainActor
    func testPictureInPictureRestoreCoordinatorCoalescesDuplicateRequests() async {
        let coordinator = PictureInPictureRestoreCoordinator.shared
        let previousHandler = coordinator.restoreHandler
        let video = VideoItem(
            bvid: "BV1PiPRestoreTest",
            aid: nil,
            title: "画中画恢复合并测试",
            pic: nil,
            desc: nil,
            duration: nil,
            pubdate: nil,
            owner: nil,
            stat: nil,
            cid: nil,
            pages: nil,
            dimension: nil
        )
        var restoreRequestCount = 0
        coordinator.restoreHandler = { _ in
            restoreRequestCount += 1
            try? await Task.sleep(nanoseconds: 20_000_000)
            return true
        }
        defer { coordinator.restoreHandler = previousHandler }

        async let firstRestore = coordinator.restorePlaybackUI(for: video)
        await Task.yield()
        async let secondRestore = coordinator.restorePlaybackUI(for: video)
        let results = await (firstRestore, secondRestore)

        XCTAssertTrue(results.0)
        XCTAssertTrue(results.1)
        XCTAssertEqual(restoreRequestCount, 1)
    }

    @MainActor
    func testAudioOnlyPlaybackContinuesWhenApplicationEntersBackground() throws {
        let coordinator = ActivePlaybackCoordinator.shared
        coordinator.stopActivePlayback()

        let engine = PlayerLifecycleEngineSpy(isPlaying: true)
        let audioURL = try XCTUnwrap(URL(string: "https://example.com/audio.m4s"))
        let player = PlayerStateViewModel(
            videoURL: nil,
            audioURL: audioURL,
            title: "听视频后台播放测试",
            referer: "https://www.bilibili.com",
            playbackContentMode: .audioOnly,
            engine: engine
        )
        coordinator.activate(player)
        player.setPlaybackIntent(true)
        defer {
            player.stop()
            coordinator.stopActivePlayback()
        }

        XCTAssertFalse(player.pauseForAppBackground())
        XCTAssertEqual(engine.backgroundPauseCallCount, 0)
        XCTAssertTrue(player.wantsAutoplay)
    }

    @MainActor
    func testDelayedStartupResumeCorrectionDoesNotRewindAdvancedAudioPlayback() async throws {
        let coordinator = ActivePlaybackCoordinator.shared
        coordinator.stopActivePlayback()

        let engine = PlayerLifecycleEngineSpy(isPlaying: true)
        engine.snapshotTime = 30
        let audioURL = try XCTUnwrap(URL(string: "https://example.com/audio.m4s"))
        let player = PlayerStateViewModel(
            videoURL: nil,
            audioURL: audioURL,
            title: "听视频前台进度测试",
            referer: "https://www.bilibili.com",
            resumeTime: 12,
            startupResumePolicy: .immediate,
            playbackContentMode: .audioOnly,
            engine: engine
        )
        let surface = VideoSurfaceContainerView()
        player.attachSurface(surface, prefersNativePlaybackControls: false)
        coordinator.activate(player)
        player.setPlaybackIntent(true)
        defer {
            player.stop()
            coordinator.stopActivePlayback()
        }

        player.play()
        try await Task.sleep(nanoseconds: 220_000_000)

        XCTAssertEqual(engine.seekCallCount, 0)
        XCTAssertEqual(engine.snapshotTime, 30)
    }

    @MainActor
    func testSeamlessPlaybackHandoffKeepsOldAudioUntilNewPlaybackStarts() {
        let coordinator = ActivePlaybackCoordinator.shared
        coordinator.stopActivePlayback()

        let oldEngine = PlayerLifecycleEngineSpy(isPlaying: true)
        oldEngine.snapshotTime = 18
        let oldPlayer = PlayerStateViewModel(
            videoURL: URL(string: "https://example.com/video.m4s"),
            audioURL: URL(string: "https://example.com/video-audio.m4s"),
            title: "原视频播放器",
            referer: "https://www.bilibili.com",
            engine: oldEngine
        )
        let newEngine = PlayerLifecycleEngineSpy(isPlaying: false)
        let newPlayer = PlayerStateViewModel(
            videoURL: nil,
            audioURL: URL(string: "https://example.com/audio-only.m4s"),
            title: "听视频播放器",
            referer: "https://www.bilibili.com",
            playbackContentMode: .audioOnly,
            engine: newEngine
        )
        let surface = VideoSurfaceContainerView()
        newPlayer.attachSurface(surface, prefersNativePlaybackControls: false)
        coordinator.activate(oldPlayer)
        defer {
            newPlayer.stop()
            oldPlayer.stop()
            coordinator.stopActivePlayback()
        }

        newPlayer.startSeamlessPlaybackHandoff(from: oldPlayer)

        XCTAssertTrue(coordinator.currentActivePlayer() === oldPlayer)
        XCTAssertEqual(oldEngine.pauseCallCount, 0)
        XCTAssertEqual(newEngine.lastSeekTime, 18)
        XCTAssertEqual(newEngine.temporaryAudioSuppressionValues.last, true)

        newEngine.onFirstFrame?(18)

        XCTAssertTrue(coordinator.currentActivePlayer() === newPlayer)
        XCTAssertGreaterThanOrEqual(oldEngine.pauseCallCount, 1)
        XCTAssertEqual(newEngine.temporaryAudioSuppressionValues.last, false)
    }

    @MainActor
    func testStoppedBackgroundPreparationFallsBackToPlayerItemWhenSoftWarmIsUnavailable() {
        let coordinator = ActivePlaybackCoordinator.shared
        coordinator.stopActivePlayback()

        let engine = PlayerLifecycleEngineSpy(isPlaying: true)
        engine.videoOutputRefreshResult = false
        engine.pausedPlaybackWarmResult = false
        let player = PlayerStateViewModel(
            videoURL: nil,
            audioURL: nil,
            title: "后台预热兜底测试",
            referer: "https://www.bilibili.com",
            engine: engine
        )
        let surface = VideoSurfaceContainerView()
        player.attachSurface(surface, prefersNativePlaybackControls: false)
        coordinator.activate(player)
        player.setPlaybackIntent(true)
        engine.onFirstFrame?(12)
        defer {
            player.stop()
            coordinator.stopActivePlayback()
        }

        XCTAssertTrue(player.pauseForAppBackground())
        XCTAssertTrue(player.prepareStoppedPlaybackAfterAppBackgroundIfNeeded())
        XCTAssertEqual(engine.videoOutputRefreshCallCount, 1)
        XCTAssertEqual(engine.pausedPlaybackWarmCallCount, 2)
        XCTAssertEqual(engine.playerItemRecoveryCallCount, 1)
        XCTAssertEqual(engine.lastPlayerItemRecoveryTime, 12)
        XCTAssertEqual(engine.playCallCount, 0)
    }

    @MainActor
    func testStoppedBackgroundManualResumeEscalatesBeforeGenericStallRecovery() async throws {
        let coordinator = ActivePlaybackCoordinator.shared
        coordinator.stopActivePlayback()

        let engine = PlayerLifecycleEngineSpy(isPlaying: true)
        let player = PlayerStateViewModel(
            videoURL: URL(string: "https://example.com/video.m4s"),
            audioURL: nil,
            title: "后台继续播放快速兜底测试",
            referer: "https://www.bilibili.com",
            engine: engine
        )
        let surface = VideoSurfaceContainerView()
        player.attachSurface(surface, prefersNativePlaybackControls: false)
        coordinator.activate(player)
        player.setPlaybackIntent(true)
        engine.onFirstFrame?(12)
        defer {
            player.stop()
            coordinator.stopActivePlayback()
        }

        XCTAssertTrue(player.pauseForAppBackground())
        XCTAssertTrue(player.prepareStoppedPlaybackAfterAppBackgroundIfNeeded())
        player.play()

        try await Task.sleep(nanoseconds: 1_800_000_000)
        XCTAssertEqual(engine.videoOutputRefreshCallCount, 2)
        XCTAssertEqual(engine.playerItemRecoveryCallCount, 1)
        XCTAssertGreaterThanOrEqual(engine.playCallCount, 3)
    }

    @MainActor
    func testExplicitPauseCancelsPendingAppBackgroundPlaybackResume() {
        let coordinator = ActivePlaybackCoordinator.shared
        coordinator.stopActivePlayback()

        let engine = PlayerLifecycleEngineSpy(isPlaying: true)
        let player = PlayerStateViewModel(
            videoURL: nil,
            audioURL: nil,
            title: "系统后台手动暂停测试",
            referer: "https://www.bilibili.com",
            isLiveStream: true,
            engine: engine
        )
        let surface = VideoSurfaceContainerView()
        player.attachSurface(surface, prefersNativePlaybackControls: false)
        coordinator.activate(player)
        player.setPlaybackIntent(true)
        defer {
            player.stop()
            coordinator.stopActivePlayback()
        }

        player.pauseForAppBackground()
        player.pause()

        XCTAssertFalse(player.resumePlaybackAfterAppBackgroundIfNeeded())
        XCTAssertEqual(engine.playCallCount, 0)
    }

    @MainActor
    func testExplicitPlayClearsStaleBackgroundIntentSoNextLockPausesAgain() {
        let coordinator = ActivePlaybackCoordinator.shared
        coordinator.stopActivePlayback()

        let engine = PlayerLifecycleEngineSpy(isPlaying: true)
        let player = PlayerStateViewModel(
            videoURL: nil,
            audioURL: nil,
            title: "连续锁屏暂停测试",
            referer: "https://www.bilibili.com",
            isLiveStream: true,
            engine: engine
        )
        let surface = VideoSurfaceContainerView()
        player.attachSurface(surface, prefersNativePlaybackControls: false)
        coordinator.activate(player)
        player.setPlaybackIntent(true)
        defer {
            player.stop()
            coordinator.stopActivePlayback()
        }

        XCTAssertTrue(player.pauseForAppBackground())
        XCTAssertEqual(engine.backgroundPauseCallCount, 1)

        player.play()
        XCTAssertTrue(player.wantsAutoplay)

        XCTAssertTrue(player.pauseForAppBackground())
        XCTAssertEqual(engine.backgroundPauseCallCount, 2)
        XCTAssertFalse(player.wantsAutoplay)
    }

    @MainActor
    func testAppBackgroundRecoveryWaitsForFreshRenderedVideoFrame() {
        let coordinator = ActivePlaybackCoordinator.shared
        coordinator.stopActivePlayback()

        let engine = PlayerLifecycleEngineSpy(isPlaying: true)
        let player = PlayerStateViewModel(
            videoURL: nil,
            audioURL: nil,
            title: "后台画面恢复测试",
            referer: "https://www.bilibili.com",
            isLiveStream: true,
            engine: engine
        )
        let surface = VideoSurfaceContainerView()
        player.attachSurface(surface, prefersNativePlaybackControls: false)
        coordinator.activate(player)
        player.setPlaybackIntent(true)
        engine.onFirstFrame?(12)
        defer {
            player.stop()
            coordinator.stopActivePlayback()
        }

        XCTAssertTrue(player.isCurrentPlaybackSurfaceReadyForDisplay)
        XCTAssertTrue(player.pauseForAppBackground())
        XCTAssertFalse(player.isCurrentPlaybackSurfaceReadyForDisplay)
        XCTAssertTrue(player.resumePlaybackAfterAppBackgroundIfNeeded())
        XCTAssertFalse(player.isCurrentPlaybackSurfaceReadyForDisplay)

        // A stale AVPlayerLayer readiness callback must not remove the held frame
        // before the video output proves that fresh media is advancing.
        engine.onFirstFrame?(12)
        XCTAssertTrue(player.isAwaitingAppBackgroundSurfaceRecovery)
        XCTAssertFalse(player.isCurrentPlaybackSurfaceReadyForDisplay)

        engine.renderedVideoTime = 12
        XCTAssertFalse(player.isAppBackgroundSurfaceRecoveryReadyForReveal())
        engine.renderedVideoTime = 12.04
        XCTAssertTrue(player.isAppBackgroundSurfaceRecoveryReadyForReveal())

        player.finishAppBackgroundSurfaceRecoveryReveal()
        XCTAssertTrue(player.isCurrentPlaybackSurfaceReadyForDisplay)
    }

    @MainActor
    func testAppBackgroundRecoveryRefreshesVideoOutputBeforeMediaRebuild() async throws {
        let coordinator = ActivePlaybackCoordinator.shared
        coordinator.stopActivePlayback()

        let engine = PlayerLifecycleEngineSpy(isPlaying: true)
        engine.playerItemRecoveryResult = nil
        let player = PlayerStateViewModel(
            videoURL: nil,
            audioURL: nil,
            title: "后台分阶段恢复测试",
            referer: "https://www.bilibili.com",
            isLiveStream: true,
            engine: engine
        )
        let surface = VideoSurfaceContainerView()
        player.attachSurface(surface, prefersNativePlaybackControls: false)
        coordinator.activate(player)
        player.setPlaybackIntent(true)
        engine.onFirstFrame?(12)
        defer {
            player.stop()
            coordinator.stopActivePlayback()
        }

        XCTAssertTrue(player.pauseForAppBackground())
        XCTAssertTrue(player.resumePlaybackAfterAppBackgroundIfNeeded())

        try await Task.sleep(nanoseconds: 1_100_000_000)
        XCTAssertEqual(engine.videoOutputRefreshCallCount, 1)
        XCTAssertEqual(engine.playerItemRecoveryCallCount, 0)
        XCTAssertEqual(engine.prepareCallCount, 0)

        try await Task.sleep(nanoseconds: 1_350_000_000)
        XCTAssertEqual(engine.videoOutputRefreshCallCount, 1)
        XCTAssertEqual(engine.playerItemRecoveryCallCount, 1)
        XCTAssertEqual(engine.prepareCallCount, 1)
    }

    @MainActor
    func testFreshRenderedFramesAfterVideoOutputRefreshAvoidMediaRebuild() async throws {
        let coordinator = ActivePlaybackCoordinator.shared
        coordinator.stopActivePlayback()

        let engine = PlayerLifecycleEngineSpy(isPlaying: true)
        let player = PlayerStateViewModel(
            videoURL: nil,
            audioURL: nil,
            title: "后台软恢复成功测试",
            referer: "https://www.bilibili.com",
            isLiveStream: true,
            engine: engine
        )
        let surface = VideoSurfaceContainerView()
        player.attachSurface(surface, prefersNativePlaybackControls: false)
        coordinator.activate(player)
        player.setPlaybackIntent(true)
        engine.onFirstFrame?(12)
        defer {
            player.stop()
            coordinator.stopActivePlayback()
        }

        XCTAssertTrue(player.pauseForAppBackground())
        XCTAssertTrue(player.resumePlaybackAfterAppBackgroundIfNeeded())

        try await Task.sleep(nanoseconds: 1_100_000_000)
        XCTAssertEqual(engine.videoOutputRefreshCallCount, 1)
        XCTAssertEqual(engine.prepareCallCount, 0)

        engine.renderedVideoTime = 12
        XCTAssertFalse(player.isAppBackgroundSurfaceRecoveryReadyForReveal())
        engine.renderedVideoTime = 12.04
        XCTAssertTrue(player.isAppBackgroundSurfaceRecoveryReadyForReveal())

        try await Task.sleep(nanoseconds: 1_350_000_000)
        XCTAssertEqual(engine.videoOutputRefreshCallCount, 1)
        XCTAssertEqual(engine.playerItemRecoveryCallCount, 0)
        XCTAssertEqual(engine.prepareCallCount, 0)
    }

    @MainActor
    func testFreshRenderedFramesAfterPlayerItemRecoveryAvoidMediaRebuild() async throws {
        let coordinator = ActivePlaybackCoordinator.shared
        coordinator.stopActivePlayback()

        let engine = PlayerLifecycleEngineSpy(isPlaying: true)
        let player = PlayerStateViewModel(
            videoURL: nil,
            audioURL: nil,
            title: "后台 PlayerItem 恢复成功测试",
            referer: "https://www.bilibili.com",
            isLiveStream: true,
            engine: engine
        )
        let surface = VideoSurfaceContainerView()
        player.attachSurface(surface, prefersNativePlaybackControls: false)
        coordinator.activate(player)
        player.setPlaybackIntent(true)
        engine.onFirstFrame?(12)
        defer {
            player.stop()
            coordinator.stopActivePlayback()
        }

        XCTAssertTrue(player.pauseForAppBackground())
        XCTAssertTrue(player.resumePlaybackAfterAppBackgroundIfNeeded())

        try await Task.sleep(nanoseconds: 2_500_000_000)
        XCTAssertEqual(engine.videoOutputRefreshCallCount, 1)
        XCTAssertEqual(engine.playerItemRecoveryCallCount, 1)
        XCTAssertEqual(engine.prepareCallCount, 0)

        engine.renderedVideoTime = 12
        XCTAssertFalse(player.isAppBackgroundSurfaceRecoveryReadyForReveal())
        engine.renderedVideoTime = 12.04
        XCTAssertTrue(player.isAppBackgroundSurfaceRecoveryReadyForReveal())

        try await Task.sleep(nanoseconds: 1_650_000_000)
        XCTAssertEqual(engine.playerItemRecoveryCallCount, 1)
        XCTAssertEqual(engine.prepareCallCount, 0)
    }

    @MainActor
    func testPlayerItemRecoveryWithoutFreshFramesFallsBackToMediaRebuild() async throws {
        let coordinator = ActivePlaybackCoordinator.shared
        coordinator.stopActivePlayback()

        let engine = PlayerLifecycleEngineSpy(isPlaying: true)
        let player = PlayerStateViewModel(
            videoURL: nil,
            audioURL: nil,
            title: "后台 PlayerItem 兜底测试",
            referer: "https://www.bilibili.com",
            isLiveStream: true,
            engine: engine
        )
        let surface = VideoSurfaceContainerView()
        player.attachSurface(surface, prefersNativePlaybackControls: false)
        coordinator.activate(player)
        player.setPlaybackIntent(true)
        engine.onFirstFrame?(12)
        defer {
            player.stop()
            coordinator.stopActivePlayback()
        }

        XCTAssertTrue(player.pauseForAppBackground())
        XCTAssertTrue(player.resumePlaybackAfterAppBackgroundIfNeeded())

        try await Task.sleep(nanoseconds: 2_500_000_000)
        XCTAssertEqual(engine.playerItemRecoveryCallCount, 1)
        XCTAssertEqual(engine.prepareCallCount, 0)

        try await Task.sleep(nanoseconds: 1_650_000_000)
        XCTAssertEqual(engine.playerItemRecoveryCallCount, 1)
        XCTAssertEqual(engine.prepareCallCount, 1)
    }

    @MainActor
    func testPictureInPictureFeatureControlsAutomaticInlinePictureInPicture() {
        let surface = VideoSurfaceContainerView()
        let isSupported = AVPictureInPictureController.isPictureInPictureSupported()

        surface.setPictureInPictureEnabled(true)

        XCTAssertEqual(surface.nativePlayerViewController.allowsPictureInPicturePlayback, isSupported)
        XCTAssertEqual(
            surface.nativePlayerViewController.canStartPictureInPictureAutomaticallyFromInline,
            isSupported
        )

        surface.setPictureInPictureEnabled(false)

        XCTAssertFalse(surface.nativePlayerViewController.allowsPictureInPicturePlayback)
        XCTAssertFalse(surface.nativePlayerViewController.canStartPictureInPictureAutomaticallyFromInline)
    }

    @MainActor
    func testDisablingPictureInPictureReleasesCustomControllerAndRemainsDisabled() throws {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            throw XCTSkip("当前测试设备不支持画中画")
        }
        let player = PlayerStateViewModel(
            videoURL: nil,
            audioURL: nil,
            title: "画中画开关测试",
            referer: "https://www.bilibili.com"
        )
        let surface = VideoSurfaceContainerView()
        defer {
            surface.detachPlayerSurface()
            player.stop()
        }

        player.attachSurface(surface, prefersNativePlaybackControls: false)
        player.setPictureInPictureEnabled(true)
        XCTAssertTrue(player.hasConfiguredPictureInPictureControllerForTesting)

        player.setPictureInPictureEnabled(false)
        player.setPictureInPictureEnabled(false)

        XCTAssertFalse(player.isPictureInPictureEnabled)
        XCTAssertFalse(player.hasConfiguredPictureInPictureControllerForTesting)
        XCTAssertFalse(surface.nativePlayerViewController.allowsPictureInPicturePlayback)
        XCTAssertFalse(surface.nativePlayerViewController.canStartPictureInPictureAutomaticallyFromInline)
    }

    @MainActor
    func testRepeatedPictureInPictureDisableStillStopsEngine() {
        let engine = PlayerLifecycleEngineSpy(isPlaying: true)
        engine.supportsPictureInPicture = true
        let player = PlayerStateViewModel(
            videoURL: nil,
            audioURL: nil,
            title: "画中画重复关闭测试",
            referer: "https://www.bilibili.com",
            engine: engine
        )
        defer { player.stop() }

        player.setPictureInPictureEnabled(true)
        player.setPictureInPictureEnabled(false)
        player.stopPictureInPictureIfNeeded()

        XCTAssertEqual(engine.pictureInPictureEnabledValues, [true, false])
        XCTAssertEqual(engine.stopPictureInPictureCallCount, 2)
        XCTAssertFalse(player.isPictureInPictureEnabled)
    }

    @MainActor
    func testVideoSurfaceContainerCanShowSystemPlaybackControls() {
        let surface = VideoSurfaceContainerView()

        XCTAssertFalse(surface.nativePlayerViewController.showsPlaybackControls)
        surface.setShowsSystemPlaybackControls(true)
        XCTAssertTrue(surface.nativePlayerViewController.showsPlaybackControls)
        XCTAssertTrue(surface.nativePlayerViewController.speeds.isEmpty)
        XCTAssertFalse(surface.nativePlayerViewController.allowsVideoFrameAnalysis)

        let engine = AVPlayerHLSBridgeEngine()
        engine.attachNativePlaybackController(surface.nativePlayerViewController)
        XCTAssertTrue(surface.nativePlayerViewController.showsPlaybackControls)
        XCTAssertTrue(surface.nativePlayerViewController.speeds.isEmpty)
        XCTAssertFalse(surface.nativePlayerViewController.allowsVideoFrameAnalysis)
        engine.detachNativePlaybackController(surface.nativePlayerViewController)
    }

    @MainActor
    func testNativePlaybackControlsInstallNonCancellingSurfaceGestures() {
        let surface = VideoSurfaceContainerView()
        let player = PlayerStateViewModel(
            videoURL: nil,
            audioURL: nil,
            title: "原生手势测试",
            referer: "https://www.bilibili.com"
        )
        defer {
            surface.detachPlayerSurface()
            player.stop()
        }

        surface.setPlayerViewModel(player, prefersNativePlaybackControls: true)
        surface.setShowsSystemPlaybackControls(true)
        surface.setNativePlaybackControllerEnabled(true)

        let gestureRecognizers = surface.nativePlayerViewController.contentOverlayView?
            .subviews
            .flatMap { $0.gestureRecognizers ?? [] }
            ?? []
        let doubleTapGesture = gestureRecognizers
            .compactMap { $0 as? UITapGestureRecognizer }
            .first { $0.numberOfTapsRequired == 2 }
        let panGesture = gestureRecognizers.first { $0 is UIPanGestureRecognizer }

        XCTAssertNotNil(doubleTapGesture)
        XCTAssertNotNil(panGesture)
        XCTAssertFalse(doubleTapGesture?.cancelsTouchesInView ?? true)
        XCTAssertFalse(panGesture?.cancelsTouchesInView ?? true)
        XCTAssertTrue(surface.nativePlayerViewController.contentOverlayView?.isUserInteractionEnabled == true)
    }

    @MainActor
    func testCoreVideoPlayerManagerUsesAVPlayer() {
        let manager = CoreVideoPlayerManager()

        XCTAssertTrue(manager.makeRenderingEngine() is AVPlayerHLSBridgeEngine)
        XCTAssertTrue(manager.makePlayer() is AVPlayerAdapter)
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "cc.bili.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}

@MainActor
final class PlayerLifecycleEngineSpy: PlayerRenderingEngine {
    var hasMedia = true
    var needsMediaRecovery = false
    var playbackErrorMessage: String?
    var lastFailureReason: HLSBridgeFailureReason?
    var supportsPictureInPicture = false
    var isPictureInPictureActive = false
    var usesNativePlaybackControls = false
    var diagnostics = PlayerEngineDiagnostics.empty
    var presentationSize = CGSize(width: 1920, height: 1080)
    var volume: Float = 1
    var isMuted = false
    var onPlaybackStateChange: (@MainActor (PlayerEnginePlaybackState) -> Void)?
    var onPlaybackIntentChange: (@MainActor (Bool) -> Void)?
    var onLoadingProgressChange: (@MainActor (Double) -> Void)?
    var onFirstFrame: (@MainActor (TimeInterval) -> Void)?

    private var isPlaying: Bool
    var snapshotTime: TimeInterval = 12
    var renderedVideoTime: TimeInterval?
    var videoOutputRefreshResult = true
    var pausedPlaybackWarmResult = true
    var playerItemRecoveryResult: TimeInterval? = 12
    private(set) var pauseCallCount = 0
    private(set) var backgroundPauseCallCount = 0
    private(set) var playCallCount = 0
    private(set) var recoverSurfaceCallCount = 0
    private(set) var videoOutputRefreshCallCount = 0
    private(set) var pausedPlaybackWarmCallCount = 0
    private(set) var playerItemRecoveryCallCount = 0
    private(set) var lastPlayerItemRecoveryTime: TimeInterval?
    private(set) var prepareCallCount = 0
    private(set) var seekCallCount = 0
    private(set) var lastSeekTime: TimeInterval?
    private(set) var temporaryAudioSuppressionValues: [Bool] = []
    private(set) var pictureInPictureEnabledValues: [Bool] = []
    private(set) var stopPictureInPictureCallCount = 0

    init(isPlaying: Bool) {
        self.isPlaying = isPlaying
    }

    func attachSurface(_: UIView) {}
    func detachSurface(_: UIView) {}
    func refreshSurfaceLayout() {}

    func recoverSurface() {
        recoverSurfaceCallCount += 1
    }

    func refreshVideoOutputForPlaybackRecovery() -> Bool {
        videoOutputRefreshCallCount += 1
        recoverSurface()
        return videoOutputRefreshResult
    }

    func rebuildPlayerItemForPlaybackRecovery(at time: TimeInterval) -> TimeInterval? {
        playerItemRecoveryCallCount += 1
        lastPlayerItemRecoveryTime = time
        return playerItemRecoveryResult
    }

    func warmPausedPlaybackForRecovery() -> Bool {
        pausedPlaybackWarmCallCount += 1
        return pausedPlaybackWarmResult
    }

    func setViewModel(_: PlayerStateViewModel?) {}
    func setVideoGravity(_: AVLayerVideoGravity) {}
    func setContentOverlay(_: AnyView?) {}
    func setDanmakuControls(isEnabled _: Bool, onToggle _: (() -> Void)?, onShowSettings _: (() -> Void)?) {}
    func setQualityControls(_: PlayerQualityControls?) {}
    func attachNativePlaybackController(_: AVPlayerViewController) {}
    func detachNativePlaybackController(_: AVPlayerViewController) {}

    func prepare(source _: PlayerStreamSource) async throws {
        prepareCallCount += 1
        hasMedia = true
    }

    func play() {
        playCallCount += 1
        isPlaying = true
        onPlaybackIntentChange?(true)
        onPlaybackStateChange?(.playing)
    }

    func pause() {
        pauseCallCount += 1
        isPlaying = false
        onPlaybackIntentChange?(false)
        onPlaybackStateChange?(.paused)
    }

    func pauseForAppBackground() {
        backgroundPauseCallCount += 1
        isPlaying = false
        onPlaybackIntentChange?(false)
        onPlaybackStateChange?(.paused)
    }

    func pauseForNavigation() {
        pause()
    }

    func suspendForNavigation() {
        pause()
    }

    func stop() {
        hasMedia = false
        isPlaying = false
    }

    func setPlaybackRate(_: Double) {}
    func setPreferredPeakBitRate(_: Double?) {}
    func setVolume(_ volume: Float) { self.volume = volume }
    func setMuted(_ isMuted: Bool) { self.isMuted = isMuted }
    func setTemporaryAudioSuppressed(_ isSuppressed: Bool) {
        temporaryAudioSuppressionValues.append(isSuppressed)
    }
    func setPictureInPictureEnabled(_ isEnabled: Bool) {
        pictureInPictureEnabledValues.append(isEnabled)
    }
    func seek(toTime time: TimeInterval) -> TimeInterval? {
        seekCallCount += 1
        lastSeekTime = time
        return time
    }
    func seekToLiveEdge() -> TimeInterval? { nil }

    func seek(toProgress progress: Double, duration: TimeInterval?) -> TimeInterval? {
        guard let duration else { return nil }
        return min(max(progress, 0), 1) * duration
    }

    func seek(by interval: TimeInterval, from currentTime: TimeInterval, duration _: TimeInterval?) -> TimeInterval? {
        max(currentTime + interval, 0)
    }

    func seekAfterUserScrub(toProgress progress: Double, duration: TimeInterval?) async -> TimeInterval? {
        seek(toProgress: progress, duration: duration)
    }

    func snapshot(durationHint: TimeInterval?) -> PlayerPlaybackSnapshot {
        PlayerPlaybackSnapshot(
            currentTime: snapshotTime,
            duration: durationHint ?? 60,
            isPlaying: isPlaying,
            isSeekable: true,
            bufferedRanges: [PlayerBufferedRange(start: 0, end: 60)]
        )
    }

    func currentVideoFrameImage() -> UIImage? { nil }
    func currentRenderedVideoTime() -> TimeInterval? { renderedVideoTime }
    func currentSurfaceSnapshotImage() -> UIImage? { nil }
    func pictureInPictureContentSource() -> AVPictureInPictureController.ContentSource? { nil }
    func togglePictureInPicture() {}
    func stopPictureInPictureIfNeeded() {
        stopPictureInPictureCallCount += 1
        isPictureInPictureActive = false
    }
    func invalidatePictureInPicturePlaybackState() {}
}
