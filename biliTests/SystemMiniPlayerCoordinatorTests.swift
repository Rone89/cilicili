import AVKit
import Combine
import UIKit
import XCTest
@testable import bili

@MainActor
final class SystemMiniPlayerCoordinatorTests: XCTestCase {
    private var suiteName: String!
    private var userDefaults: UserDefaults!
    private var libraryStore: LibraryStore!

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            suiteName = "cc.bili.tests.SystemMiniPlayer.\(UUID().uuidString)"
            userDefaults = UserDefaults(suiteName: suiteName)!
            libraryStore = LibraryStore(userDefaults: userDefaults)
            SystemMiniPlayerCoordinator.shared.resetForTesting()
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            SystemMiniPlayerCoordinator.shared.resetForTesting()
            userDefaults.removePersistentDomain(forName: suiteName)
            libraryStore = nil
            userDefaults = nil
            suiteName = nil
        }
        super.tearDown()
    }

    func testAutoPictureInPictureOnExitSettingDefaultsFalseAndAllowsControllerWithoutAutoBackgroundPiP() {
        XCTAssertFalse(libraryStore.autoPictureInPictureOnExitEnabled)
        XCTAssertFalse(libraryStore.pictureInPictureEnabled)
        XCTAssertFalse(libraryStore.allowsPictureInPictureController)

        libraryStore.setAutoPictureInPictureOnExitEnabled(true)
        XCTAssertTrue(libraryStore.autoPictureInPictureOnExitEnabled)
        XCTAssertFalse(libraryStore.pictureInPictureEnabled)
        XCTAssertTrue(libraryStore.allowsPictureInPictureController)

        let runtimeStore = VideoDetailRuntimeSettingsStore()
        runtimeStore.bind(libraryStore)
        XCTAssertTrue(runtimeStore.autoPictureInPictureOnExitEnabled)
        XCTAssertTrue(runtimeStore.allowsPictureInPictureController)
    }

    func testPlayingVideoExitWithSettingEnabledTransfersToMiniPlayerWithoutStopping() {
        libraryStore.setAutoPictureInPictureOnExitEnabled(true)
        let video = makeVideo(bvid: "BV1ExitMiniPlay", cid: 101)
        let (detailVM, engine, player) = makePlayingDetailViewModel(video: video)

        let coordinator = SystemMiniPlayerCoordinator.shared
        coordinator.supportsPictureInPicture = { true }
        var attachCallCount = 0
        var startPiPCallCount = 0
        coordinator.onAttachStagingSurface = { _, _, _, allowsAutoInline in
            attachCallCount += 1
            XCTAssertFalse(allowsAutoInline)
        }
        coordinator.onStartPictureInPicture = { _, _ in
            startPiPCallCount += 1
        }

        detailVM.markExitingVideoDetailRoute()
        detailVM.stopPlaybackForNavigation()

        XCTAssertEqual(attachCallCount, 1)
        XCTAssertEqual(startPiPCallCount, 1)
        XCTAssertNotNil(coordinator.activeSession)
        XCTAssertEqual(coordinator.activeSession?.video.bvid, "BV1ExitMiniPlay")
        XCTAssertTrue(coordinator.activeSession?.playerViewModel === player)
        XCTAssertNil(detailVM.stablePlayerViewModel)
        XCTAssertEqual(engine.stopCallCount, 0)
        XCTAssertEqual(engine.pauseCallCount, 0)
        XCTAssertTrue(engine.isPlaying)
    }

    func testPausedVideoExitDoesNotTriggerMiniPlayer() {
        libraryStore.setAutoPictureInPictureOnExitEnabled(true)
        let video = makeVideo(bvid: "BV1ExitMiniPause", cid: 102)
        let (detailVM, engine, player) = makePlayingDetailViewModel(video: video)
        player.pause()
        let pauseBeforeExit = engine.pauseCallCount

        let coordinator = SystemMiniPlayerCoordinator.shared
        coordinator.supportsPictureInPicture = { true }
        var startPiPCallCount = 0
        coordinator.onStartPictureInPicture = { _, _ in
            startPiPCallCount += 1
        }

        detailVM.markExitingVideoDetailRoute()
        detailVM.stopPlaybackForNavigation()

        XCTAssertEqual(startPiPCallCount, 0)
        XCTAssertNil(coordinator.activeSession)
        XCTAssertGreaterThanOrEqual(engine.pauseCallCount, pauseBeforeExit)
    }

    func testRelatedVideoPushDoesNotTriggerMiniPlayerEvenWhenExitSwitchEnabled() {
        libraryStore.setAutoPictureInPictureOnExitEnabled(true)
        let video = makeVideo(bvid: "BV1RelatedNoPiP", cid: 103)
        let (detailVM, engine, _) = makePlayingDetailViewModel(video: video)

        let coordinator = SystemMiniPlayerCoordinator.shared
        coordinator.supportsPictureInPicture = { true }
        var startPiPCallCount = 0
        coordinator.onStartPictureInPicture = { _, _ in
            startPiPCallCount += 1
        }

        detailVM.markRelatedVideoNavigation()
        detailVM.stopPlaybackForNavigation()

        XCTAssertEqual(startPiPCallCount, 0)
        XCTAssertNil(coordinator.activeSession)
        XCTAssertEqual(engine.pauseCallCount, 1)
    }

    func testDisabledAutoExitSwitchStopsPlaybackNormally() {
        libraryStore.setAutoPictureInPictureOnExitEnabled(false)
        let video = makeVideo(bvid: "BV1ExitOff", cid: 104)
        let (detailVM, engine, _) = makePlayingDetailViewModel(video: video)

        let coordinator = SystemMiniPlayerCoordinator.shared
        coordinator.supportsPictureInPicture = { true }
        var startPiPCallCount = 0
        coordinator.onStartPictureInPicture = { _, _ in
            startPiPCallCount += 1
        }

        detailVM.markExitingVideoDetailRoute()
        detailVM.stopPlaybackForNavigation()
        detailVM.finishPlaybackStopAfterNavigationTransition()

        XCTAssertEqual(startPiPCallCount, 0)
        XCTAssertNil(coordinator.activeSession)
        XCTAssertEqual(engine.stopCallCount, 1)
    }

    func testAudioOnlyListenModeDoesNotTriggerMiniPlayer() {
        libraryStore.setAutoPictureInPictureOnExitEnabled(true)
        let video = makeVideo(bvid: "BV1AudioOnlyNoPiP", cid: 105)
        let (detailVM, _, player) = makePlayingDetailViewModel(
            video: video,
            contentMode: .audioOnly
        )
        detailVM.playbackContentMode = .audioOnly

        let coordinator = SystemMiniPlayerCoordinator.shared
        coordinator.supportsPictureInPicture = { true }
        var startPiPCallCount = 0
        coordinator.onStartPictureInPicture = { _, _ in
            startPiPCallCount += 1
        }

        XCTAssertFalse(player.isEligibleForExitPictureInPicture)
        detailVM.markExitingVideoDetailRoute()
        detailVM.stopPlaybackForNavigation()

        XCTAssertEqual(startPiPCallCount, 0)
        XCTAssertNil(coordinator.activeSession)
    }

    func testClaimMatchingSessionAdoptsSamePlayerWithoutRecreating() {
        libraryStore.setAutoPictureInPictureOnExitEnabled(true)
        let video = makeVideo(bvid: "BV1AdoptSame", cid: 201)
        let (detailVM, engine, originalPlayer) = makePlayingDetailViewModel(video: video)

        let coordinator = SystemMiniPlayerCoordinator.shared
        coordinator.supportsPictureInPicture = { true }
        coordinator.onAttachStagingSurface = { _, _, _, _ in }
        coordinator.onDetachStagingSurface = { _, _ in }
        coordinator.onStartPictureInPicture = { _, _ in }

        detailVM.markExitingVideoDetailRoute()
        detailVM.stopPlaybackForNavigation()
        XCTAssertNotNil(coordinator.activeSession)

        let sessionStore = SessionStore()
        let holder = VideoDetailViewModelHolder()
        holder.configure(
            seedVideo: video,
            api: BiliAPIClient(
                sessionStore: sessionStore,
                libraryStore: libraryStore,
                homeRecommendDiagnosticsStore: .shared
            ),
            libraryStore: libraryStore,
            sessionStore: sessionStore,
            sponsorBlockService: SponsorBlockService()
        )

        XCTAssertNil(coordinator.activeSession)
        XCTAssertEqual(detailVM.didTransferToSystemMiniPlayer, true)
        XCTAssertTrue(holder.viewModel?.stablePlayerViewModel === originalPlayer)
        XCTAssertEqual(holder.viewModel?.state, .loaded)
        XCTAssertEqual(engine.stopCallCount, 0)
    }

    func testOpeningDifferentVideoStopsRetainedMiniPlayerSession() {
        libraryStore.setAutoPictureInPictureOnExitEnabled(true)
        let videoA = makeVideo(bvid: "BV1VideoA", cid: 301)
        let videoB = makeVideo(bvid: "BV1VideoB", cid: 302)
        let (detailVM, engineA, _) = makePlayingDetailViewModel(video: videoA)

        let coordinator = SystemMiniPlayerCoordinator.shared
        coordinator.supportsPictureInPicture = { true }
        coordinator.onAttachStagingSurface = { _, _, _, _ in }
        coordinator.onDetachStagingSurface = { _, _ in }
        coordinator.onStartPictureInPicture = { _, _ in }

        detailVM.markExitingVideoDetailRoute()
        detailVM.stopPlaybackForNavigation()
        XCTAssertNotNil(coordinator.activeSession)

        let sessionStoreB = SessionStore()
        let holderB = VideoDetailViewModelHolder()
        holderB.configure(
            seedVideo: videoB,
            api: BiliAPIClient(
                sessionStore: sessionStoreB,
                libraryStore: libraryStore,
                homeRecommendDiagnosticsStore: .shared
            ),
            libraryStore: libraryStore,
            sessionStore: sessionStoreB,
            sponsorBlockService: SponsorBlockService()
        )

        XCTAssertNil(coordinator.activeSession)
        XCTAssertEqual(engineA.stopCallCount, 1)
    }

    func testClosingSystemPictureInPictureStopsRetainedPlayerAndFailureCleansUp() {
        libraryStore.setAutoPictureInPictureOnExitEnabled(true)
        let video = makeVideo(bvid: "BV1ClosePiP", cid: 401)
        let (detailVM, engine, player) = makePlayingDetailViewModel(video: video)

        let coordinator = SystemMiniPlayerCoordinator.shared
        coordinator.supportsPictureInPicture = { true }
        coordinator.onAttachStagingSurface = { _, _, _, _ in }
        coordinator.onDetachStagingSurface = { _, _ in }
        var capturedFailure: (() -> Void)?
        coordinator.onStartPictureInPicture = { _, onFailure in
            capturedFailure = onFailure
        }

        detailVM.markExitingVideoDetailRoute()
        detailVM.stopPlaybackForNavigation()
        XCTAssertNotNil(coordinator.activeSession)

        player.onPictureInPictureDidStop?()
        XCTAssertNil(coordinator.activeSession)
        XCTAssertEqual(engine.stopCallCount, 1)

        // Verify failure callback also cleans up an active session safely.
        let video2 = makeVideo(bvid: "BV1FailPiP", cid: 402)
        let (detailVM2, engine2, _) = makePlayingDetailViewModel(video: video2)
        detailVM2.markExitingVideoDetailRoute()
        detailVM2.stopPlaybackForNavigation()
        XCTAssertNotNil(coordinator.activeSession)
        capturedFailure?()
        XCTAssertNil(coordinator.activeSession)
        XCTAssertEqual(engine2.stopCallCount, 1)
    }

    func testSwipeBackRouteRemovalWithoutExplicitMarkTriggersMiniPlayer() {
        libraryStore.setAutoPictureInPictureOnExitEnabled(true)
        let video = makeVideo(bvid: "BV1SwipeExit", cid: 501)
        let (detailVM, engine, _) = makePlayingDetailViewModel(video: video)

        let coordinator = SystemMiniPlayerCoordinator.shared
        coordinator.supportsPictureInPicture = { true }
        var attachCallCount = 0
        var startCallCount = 0
        coordinator.onAttachStagingSurface = { _, _, _, _ in attachCallCount += 1 }
        coordinator.onDetachStagingSurface = { _, _ in }
        coordinator.onStartPictureInPicture = { _, _ in startCallCount += 1 }

        detailVM.isRouteRemovedFromNavigationStack = { true }
        detailVM.stopPlaybackForNavigation()

        XCTAssertNotNil(coordinator.activeSession)
        XCTAssertEqual(coordinator.activeSession?.video.bvid, "BV1SwipeExit")
        XCTAssertEqual(attachCallCount, 1)
        XCTAssertEqual(startCallCount, 1)
        XCTAssertEqual(engine.pauseCallCount, 0)
        XCTAssertEqual(engine.stopCallCount, 0)
    }

    func testCoveredRoutePushWithRouteStillInNavigationStackDoesNotTriggerMiniPlayer() {
        libraryStore.setAutoPictureInPictureOnExitEnabled(true)
        let video = makeVideo(bvid: "BV1CoveredPush", cid: 502)
        let (detailVM, engine, _) = makePlayingDetailViewModel(video: video)

        let coordinator = SystemMiniPlayerCoordinator.shared
        coordinator.supportsPictureInPicture = { true }
        var startCallCount = 0
        coordinator.onAttachStagingSurface = { _, _, _, _ in }
        coordinator.onDetachStagingSurface = { _, _ in }
        coordinator.onStartPictureInPicture = { _, _ in startCallCount += 1 }

        detailVM.isRouteRemovedFromNavigationStack = { false }
        detailVM.stopPlaybackForNavigation()

        XCTAssertNil(coordinator.activeSession)
        XCTAssertEqual(startCallCount, 0)
        XCTAssertEqual(engine.pauseCallCount, 1)
    }

    private func makeVideo(bvid: String, cid: Int) -> VideoItem {
        VideoItem(
            bvid: bvid,
            aid: 123456,
            title: "小窗测试视频 \(bvid)",
            pic: nil,
            desc: nil,
            duration: 180,
            pubdate: nil,
            owner: nil,
            stat: nil,
            cid: cid,
            pages: [VideoPage(cid: cid, page: 1, part: "P1", duration: 180, dimension: nil)],
            dimension: nil
        )
    }

    private func makePlayingDetailViewModel(
        video: VideoItem,
        contentMode: PlayerPlaybackContentMode = .video
    ) -> (VideoDetailViewModel, StubMiniPlayerRenderingEngine, PlayerStateViewModel) {
        let engine = StubMiniPlayerRenderingEngine()
        let player = PlayerStateViewModel(
            videoURL: contentMode == .video ? URL(string: "https://example.com/v.m4s") : nil,
            audioURL: URL(string: "https://example.com/a.m4s"),
            title: video.title,
            referer: "https://www.bilibili.com/video/\(video.bvid)",
            durationHint: 180,
            startupResumePolicy: .immediate,
            playbackContentMode: contentMode,
            engine: engine
        )
        let sessionStore = SessionStore()
        let detailVM = VideoDetailViewModel(
            seedVideo: video,
            api: BiliAPIClient(
                sessionStore: sessionStore,
                libraryStore: libraryStore,
                homeRecommendDiagnosticsStore: .shared
            ),
            libraryStore: libraryStore,
            sessionStore: sessionStore,
            sponsorBlockService: SponsorBlockService()
        )
        let variant = PlayVariant(
            quality: 80,
            title: "1080P",
            videoURL: URL(string: "https://example.com/v.m4s"),
            audioURL: URL(string: "https://example.com/a.m4s"),
            videoStream: nil,
            audioStream: nil,
            codec: "AVC",
            resolution: nil,
            frameRate: "30",
            bandwidth: 2_000_000,
            isHDR: false,
            badge: nil
        )
        detailVM.playVariants = [variant]
        detailVM.selectedPlayVariant = variant
        detailVM.state = LoadingState.loaded
        detailVM.playURLState = LoadingState.loaded
        detailVM.installStablePlayerViewModel(
            player,
            variant: variant,
            resumeCandidate: PlaybackResumeCandidate(time: 0, sourceTitle: "test", reason: "test", cid: video.cid),
            resumeTime: 0,
            playbackRate: .x10,
            shouldAutoplay: true,
            playbackHandoffSource: nil
        )
        engine.play()
        return (detailVM, engine, player)
    }
}

@MainActor
private final class StubMiniPlayerRenderingEngine: PlayerRenderingEngine {
    private(set) var hasMedia = true
    private(set) var isPlaying = false
    private(set) var stopCallCount = 0
    private(set) var pauseCallCount = 0
    var playbackErrorMessage: String? { nil }
    var needsMediaRecovery: Bool { false }
    var lastFailureReason: HLSBridgeFailureReason? { nil }
    var supportsPictureInPicture: Bool { true }
    var isPictureInPictureActive = false
    var usesNativePlaybackControls: Bool { false }
    var diagnostics: PlayerEngineDiagnostics { .empty }
    var presentationSize: CGSize { CGSize(width: 1920, height: 1080) }
    var volume: Float = 1
    var isMuted = false
    var onPlaybackStateChange: (@MainActor (PlayerEnginePlaybackState) -> Void)?
    var onPlaybackIntentChange: (@MainActor (Bool) -> Void)?
    var onLoadingProgressChange: (@MainActor (Double) -> Void)?
    var onFirstFrame: (@MainActor (TimeInterval) -> Void)?

    func attachSurface(_: UIView) {}
    func detachSurface(_: UIView) {}
    func refreshSurfaceLayout() {}
    func recoverSurface() {}
    func setViewModel(_: PlayerStateViewModel?) {}
    func setVideoGravity(_: AVLayerVideoGravity) {}
    func attachNativePlaybackController(_: AVPlayerViewController) {}
    func detachNativePlaybackController(_: AVPlayerViewController) {}

    func prepare(source _: PlayerStreamSource) async throws {
        hasMedia = true
        onPlaybackStateChange?(.ready)
    }

    func play() {
        isPlaying = true
        onPlaybackIntentChange?(true)
        onPlaybackStateChange?(.playing)
        onFirstFrame?(12)
    }

    func pause() {
        pauseCallCount += 1
        isPlaying = false
        onPlaybackIntentChange?(false)
        onPlaybackStateChange?(.paused)
    }

    func pauseForAppBackground() {
        pause()
    }

    func pauseForNavigation() {
        pause()
    }

    func suspendForNavigation() {
        pause()
    }

    func stop() {
        stopCallCount += 1
        hasMedia = false
        isPlaying = false
    }

    func setPlaybackRate(_: Double) {}
    func setPreferredPeakBitRate(_: Double?) {}
    func setVolume(_ volume: Float) { self.volume = volume }
    func setMuted(_ isMuted: Bool) { self.isMuted = isMuted }
    func setTemporaryAudioSuppressed(_: Bool) {}
    func setPictureInPictureEnabled(_: Bool) {}
    func seek(toTime time: TimeInterval) -> TimeInterval? { time }
    func seekToLiveEdge() -> TimeInterval? { nil }
    func seek(toProgress progress: Double, duration: TimeInterval?) -> TimeInterval? {
        guard let duration else { return nil }
        return progress * duration
    }
    func seek(by interval: TimeInterval, from currentTime: TimeInterval, duration _: TimeInterval?) -> TimeInterval? {
        max(currentTime + interval, 0)
    }
    func seekAfterUserScrub(toProgress progress: Double, duration: TimeInterval?) async -> TimeInterval? {
        seek(toProgress: progress, duration: duration)
    }
    func snapshot(durationHint: TimeInterval?) -> PlayerPlaybackSnapshot {
        PlayerPlaybackSnapshot(
            currentTime: 12,
            renderedVideoTime: 12,
            requiresRenderedVideoTimeForRecovery: false,
            duration: durationHint ?? 180,
            isPlaying: isPlaying,
            isSeekable: true,
            bufferedRanges: [],
            bufferObservationAvailable: true
        )
    }
    func recoveryBufferSnapshot() -> PlayerPlaybackSnapshot? { snapshot(durationHint: 180) }
    func currentVideoFrameImage() -> UIImage? { nil }
    func currentRenderedVideoTime() -> TimeInterval? { 12 }
    func currentSurfaceSnapshotImage() -> UIImage? { nil }
    func pictureInPictureContentSource() -> AVPictureInPictureController.ContentSource? { nil }
    func togglePictureInPicture() { isPictureInPictureActive.toggle() }
    func stopPictureInPictureIfNeeded() { isPictureInPictureActive = false }
    func invalidatePictureInPicturePlaybackState() {}
}
