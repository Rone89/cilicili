import AVKit
import Combine
import SwiftUI
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

    func testAutoExitStagingHostMountsUnoccludedAndSinksAfterPiPStarts() async throws {
        libraryStore.setAutoPictureInPictureOnExitEnabled(true)
        let localVideoURL = try await makeLocalTestVideoURL()
        defer { try? FileManager.default.removeItem(at: localVideoURL) }

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 430, height: 932)
        let rootVC = UIViewController()
        let opaqueFeedView = UIView(frame: window.bounds)
        opaqueFeedView.backgroundColor = .systemBackground
        rootVC.view.addSubview(opaqueFeedView)
        window.rootViewController = rootVC
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }

        let engine = AVPlayerHLSBridgeEngine()
        let player = PlayerStateViewModel(
            videoURL: localVideoURL,
            audioURL: nil,
            title: "Staging Visibility Test",
            referer: "https://www.bilibili.com",
            durationHint: 4,
            engine: engine
        )
        let detailHost = DirectUIKitPlayerSurfaceHostView(
            viewModel: player,
            isPictureInPictureEnabled: true,
            allowsAutomaticPictureInPictureFromInline: false,
            prefersNativePlaybackSurface: true
        )
        detailHost.frame = CGRect(x: 0, y: 59, width: 430, height: 242)
        rootVC.view.addSubview(detailHost)
        rootVC.view.layoutIfNeeded()
        defer {
            detailHost.tearDown()
            detailHost.removeFromSuperview()
            player.stop()
        }

        XCTAssertNotNil(detailHost.nativePlayerViewController.player)
        XCTAssertFalse(detailHost.nativePlayerViewController.canStartPictureInPictureAutomaticallyFromInline)

        let video = makeVideo(bvid: "BV1StageFront", cid: 901)
        let sessionStore = SessionStore()
        let detailVM = VideoDetailViewModel(
            seedVideo: video,
            api: BiliAPIClient(sessionStore: sessionStore, libraryStore: libraryStore, homeRecommendDiagnosticsStore: .shared),
            libraryStore: libraryStore,
            sessionStore: sessionStore,
            sponsorBlockService: SponsorBlockService()
        )
        let variant = PlayVariant(
            quality: 80, title: "1080P", videoURL: localVideoURL,
            audioURL: nil, videoStream: nil, audioStream: nil,
            codec: "AVC", resolution: nil, frameRate: "15", bandwidth: 2_000_000, isHDR: false, badge: nil
        )
        detailVM.playVariants = [variant]
        detailVM.selectedPlayVariant = variant
        detailVM.state = .loaded
        detailVM.playURLState = .loaded
        detailVM.installStablePlayerViewModel(
            player,
            variant: variant,
            resumeCandidate: PlaybackResumeCandidate(time: 0, sourceTitle: "test", reason: "test", cid: 901),
            resumeTime: 0,
            playbackRate: .x10,
            shouldAutoplay: true,
            playbackHandoffSource: nil
        )
        detailVM.playerWindowFrameProvider = {
            (CGRect(x: 0, y: 59, width: 430, height: 242), window)
        }

        for _ in 0..<80 {
            if player.isPlaying && player.hasPresentedPlayback { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(player.isPlaying)
        XCTAssertTrue(player.hasPresentedPlayback)

        let coordinator = SystemMiniPlayerCoordinator.shared
        coordinator.supportsPictureInPicture = { true }
        var startCallCount = 0
        coordinator.onStartPictureInPicture = { _, _ in
            startCallCount += 1
        }

        detailVM.markExitingVideoDetailRoute()
        detailVM.stopPlaybackForNavigation()

        XCTAssertEqual(startCallCount, 1)
        XCTAssertNotNil(coordinator.activeSession)
        // Native AVPlayerViewController must be detached and replaced with an unoccluded AVPlayerLayer staging surface
        // mounted directly on the window above SwiftUI's UIHostingController.view.
        XCTAssertNil(detailHost.nativePlayerViewController.player)
        XCTAssertNil(rootVC.view.subviews.compactMap { $0 as? SystemMiniPlayerStagingView }.first)
        let stagingHost = try XCTUnwrap(window.subviews.compactMap { $0 as? SystemMiniPlayerStagingView }.first)
        XCTAssertTrue(window.subviews.last === stagingHost)
        XCTAssertEqual(stagingHost.alpha, 1.0, accuracy: 0.001)
        XCTAssertEqual(stagingHost.frame, CGRect(x: 0, y: 59, width: 430, height: 242))
        XCTAssertTrue(
            stagingHost.surfaceView.drawableView.layer.sublayers?.contains(where: { $0 is AVPlayerLayer }) == true
        )

        // Once PiP finishes starting, staging dims and moves behind root views without detaching from window.
        player.onPictureInPictureDidStart?()
        XCTAssertLessThan(stagingHost.alpha, 0.05)
        XCTAssertTrue(window.subviews.first === stagingHost)

        coordinator.stopActiveMiniPlayer()
        XCTAssertNil(stagingHost.superview)
        XCTAssertEqual(stagingHost.alpha, 1.0, accuracy: 0.001)
    }

    private func makeLocalTestVideoURL() async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 320,
            AVVideoHeightKey: 180,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: 320,
                kCVPixelBufferHeightKey as String: 180,
            ]
        )
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for index in 0...60 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            if let pixelBuffer = buffer {
                CVPixelBufferLockBaseAddress(pixelBuffer, [])
                if let bytes = CVPixelBufferGetBaseAddress(pixelBuffer)?.assumingMemoryBound(to: UInt8.self) {
                    let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
                    for y in 0..<180 {
                        for x in 0..<320 {
                            let offset = y * stride + x * 4
                            bytes[offset] = 255
                            bytes[offset + 1] = 200
                            bytes[offset + 2] = 60
                            bytes[offset + 3] = 40
                        }
                    }
                }
                CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
                adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: Int64(index), timescale: 15))
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        return url
    }

    func testAutoExitOnlyModeKeepsAutomaticInlinePiPDisabledOnNativeController() throws {
        let engine = AVPlayerHLSBridgeEngine()
        let player = PlayerStateViewModel(
            videoURL: URL(string: "https://example.com/v.m4s"),
            audioURL: URL(string: "https://example.com/a.m4s"),
            title: "Auto Inline PiP Guard",
            referer: "https://www.bilibili.com",
            engine: engine
        )
        let surfaceHost = DirectUIKitPlayerSurfaceHostView(
            viewModel: player,
            isPictureInPictureEnabled: true,
            allowsAutomaticPictureInPictureFromInline: false,
            prefersNativePlaybackSurface: true,
            showsNativePlaybackControls: true,
            showsNativePlaybackSpeeds: true,
            enablesNativeSurfaceGestures: false,
            nativeAllowsPictureInPicturePlayback: nil
        )
        defer {
            surfaceHost.tearDown()
            player.stop()
        }

        XCTAssertFalse(surfaceHost.nativePlayerViewController.canStartPictureInPictureAutomaticallyFromInline)
        surfaceHost.setNativePlaybackControlsOptions(
            prefersNativePlaybackSurface: true,
            showsPlaybackControls: false,
            showsPlaybackSpeeds: true,
            enablesNativeSurfaceGestures: true,
            allowsPictureInPicturePlayback: nil
        )
        XCTAssertFalse(surfaceHost.nativePlayerViewController.canStartPictureInPictureAutomaticallyFromInline)
        engine.setPictureInPictureEnabled(true)
        XCTAssertFalse(surfaceHost.nativePlayerViewController.canStartPictureInPictureAutomaticallyFromInline)
    }

    func testNavigationStackExitSurfaceHandoffProbe() async throws {
        final class Driver: ObservableObject {
            @Published var path = NavigationPath()
        }
        struct Host: View {
            @ObservedObject var driver: Driver
            @ObservedObject var libraryStore: LibraryStore
            let dependencies: AppDependencies
            @State private var usesVideoStatusBarContrast = false
            @State private var videoContentColorScheme: ColorScheme?
            var body: some View {
                TabView {
                    Tab("首页", systemImage: "house") {
                        NavigationStack(path: $driver.path) {
                            ScrollView { Text("Root").frame(height: 1200) }
                                .videoDestinations(
                                    usesTransparentNavigationBar: true,
                                    navigationBarColorScheme: videoContentColorScheme
                                )
                        }
                        .coordinatesRootTabBarTransitions(
                            isDetailPresented: !driver.path.isEmpty,
                            hidesRootTabBar: false
                        )
                        .navigationHistoryStack(path: $driver.path, rootTitle: "首页")
                        .nativeBottomScrollEdgeBlur()
                    }
                }
                .environmentObject(dependencies)
                .environmentObject(dependencies.sessionStore)
                .environmentObject(libraryStore)
                .environmentObject(dependencies.homeRecommendDiagnosticsStore)
                .preferredColorScheme(usesVideoStatusBarContrast ? .dark : nil)
                .onPreferenceChange(VideoDetailStatusBarContrastPreferenceKey.self) { active in
                    guard usesVideoStatusBarContrast != active else { return }
                    videoContentColorScheme = active ? .light : nil
                    usesVideoStatusBarContrast = active
                }
            }
        }

        let mediaURL = try await makeLocalTestVideoURL()
        defer { try? FileManager.default.removeItem(at: mediaURL) }

        let deps = AppDependencies()
        let prevAutoExit = deps.libraryStore.autoPictureInPictureOnExitEnabled
        let prevPiP = deps.libraryStore.pictureInPictureEnabled
        deps.libraryStore.setAutoPictureInPictureOnExitEnabled(true)
        deps.libraryStore.setPictureInPictureEnabled(false)
        defer {
            deps.libraryStore.setAutoPictureInPictureOnExitEnabled(prevAutoExit)
            deps.libraryStore.setPictureInPictureEnabled(prevPiP)
        }
        let video = makeVideo(bvid: "BV1NavStackExitProbe", cid: 201)

        // Seed an active playing session in SystemMiniPlayerCoordinator so VideoDetailView
        // immediately adopts a live local-video player without hitting the network.
        let engine = AVPlayerHLSBridgeEngine()
        let player = PlayerStateViewModel(
            videoURL: mediaURL,
            audioURL: nil,
            title: video.title,
            referer: "https://www.bilibili.com/video/\(video.bvid)",
            durationHint: 4,
            engine: engine
        )
        let hostSetupView = VideoSurfaceContainerView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        player.attachSurface(hostSetupView, prefersNativePlaybackControls: false)
        try await engine.prepare(source: PlayerStreamSource(
            metricsID: video.bvid,
            videoURL: mediaURL,
            audioURL: nil,
            videoStream: nil,
            audioStream: nil,
            alternateVideoRenditions: [],
            referer: "https://www.bilibili.com/video/\(video.bvid)",
            httpHeaders: [:],
            title: video.title,
            durationHint: 4,
            isLiveStream: false,
            isLiveHLS: false,
            liveHLSFormat: nil,
            resumeTime: 0,
            dynamicRange: .sdr,
            cdnPreference: .automatic
        ))
        player.play()
        let readyDeadline = Date().addingTimeInterval(3.0)
        while !player.isEligibleForExitPictureInPicture && Date() < readyDeadline {
            try await Task.sleep(for: .milliseconds(30))
        }
        XCTAssertTrue(player.isEligibleForExitPictureInPicture)

        var events: [String] = []
        player.onVideoDetailPlaybackDiagnosticSurfaceEvent = { event in
            switch event {
            case .attached(let surfaceID, _, _):
                events.append("attached:\(surfaceID.hashValue)")
                print("[Probe] surfaceAttached id=\(surfaceID.hashValue) nativeVC=\(player.usesNativePlaybackSurfaceController)")
            case .detached(let surfaceID, _, _):
                events.append("detached:\(surfaceID.hashValue)")
                print("[Probe] surfaceDetached id=\(surfaceID.hashValue)")
            }
        }

        let coordinator = SystemMiniPlayerCoordinator.shared
        coordinator.supportsPictureInPicture = { true }
        coordinator.onStartPictureInPicture = { player, _ in
            print("[Probe] onStartPictureInPicture active=\(player.isPictureInPictureActive)")
        }

        let didBeginInitial = coordinator.beginMiniPlayer(
            with: .init(
                video: video,
                selectedCID: 201,
                playVariants: [],
                selectedPlayVariant: nil,
                currentPlayURLData: nil,
                isDanmakuEnabled: true,
                hasResolvedDetailMetadata: true,
                stablePlayerIdentity: "probe",
                playerViewModel: player,
                recordsPlaybackHistory: false,
                api: deps.api,
                libraryStore: deps.libraryStore,
                isRestoringUserInterface: true
            )
        )
        XCTAssertTrue(didBeginInitial)

        let driver = Driver()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let hostVC = UIHostingController(rootView: Host(driver: driver, libraryStore: deps.libraryStore, dependencies: deps))
        window.rootViewController = hostVC
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            coordinator.resetForTesting()
            player.stop()
        }

        try await Task.sleep(for: .milliseconds(300))
        let prePushEvents = events.count
        print("[Probe] pushing detail")
        driver.path.append(video)
        let mountDeadline = Date().addingTimeInterval(3.0)
        while events.count <= prePushEvents && Date() < mountDeadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        try await Task.sleep(for: .milliseconds(500))

        let eventsBeforePop = events.count
        print("[Probe] popping detail (events so far=\(eventsBeforePop))")
        if let detailVM = VideoDetailPlaybackLocator.currentViewModel {
            detailVM.markExitingVideoDetailRoute()
            detailVM.stopPlaybackForNavigation()
        }
        driver.path.removeLast()

        try await Task.sleep(for: .milliseconds(1500))
        print("[Probe] after pop events=\(events.dropFirst(eventsBeforePop))")
        XCTAssertEqual(driver.path.count, 0)
        XCTAssertTrue(coordinator.activeSession?.playerViewModel === player)
        XCTAssertFalse(player.usesNativePlaybackSurfaceController)
        let stagingHost = try XCTUnwrap(window.subviews.compactMap { $0 as? SystemMiniPlayerStagingView }.first)
        XCTAssertNil(hostVC.view.subviews.compactMap { $0 as? SystemMiniPlayerStagingView }.first)
        XCTAssertTrue(stagingHost.surfaceView.isBound(to: player))
        XCTAssertTrue(
            stagingHost.surfaceView.drawableView.layer.sublayers?.contains(where: { $0 is AVPlayerLayer }) == true
        )
    }

    @MainActor
    func testRestoreUserInterfaceBeforePictureInPictureStartsIsIgnored() async {
        libraryStore.setAutoPictureInPictureOnExitEnabled(true)
        let coordinator = SystemMiniPlayerCoordinator.shared
        coordinator.resetForTesting()
        let restoreCoordinator = PictureInPictureRestoreCoordinator.shared
        let previousRestoreHandler = restoreCoordinator.restoreHandler
        defer {
            restoreCoordinator.restoreHandler = previousRestoreHandler
            coordinator.resetForTesting()
        }

        let video = makeVideo(bvid: "BV1NotStarted", cid: 901)
        let (detailVM, _, player) = makePlayingDetailViewModel(video: video)
        player.setPictureInPictureEnabled(true)
        defer { player.stop() }

        coordinator.supportsPictureInPicture = { true }
        coordinator.onAttachStagingSurface = { _, _, _, _ in }
        coordinator.onStartPictureInPicture = { _, _ in }

        var restoreCalls = 0
        restoreCoordinator.restoreHandler = { _ in
            restoreCalls += 1
            return true
        }

        detailVM.markExitingVideoDetailRoute()
        detailVM.stopPlaybackForNavigation()
        XCTAssertNotNil(coordinator.activeSession)

        let earlyRestore = await player.restoreUserInterfaceForPictureInPictureStop?()
        XCTAssertEqual(earlyRestore, false)
        XCTAssertEqual(restoreCalls, 0)

        player.onPictureInPictureDidStart?()
        let activeRestore = await player.restoreUserInterfaceForPictureInPictureStop?()
        XCTAssertEqual(activeRestore, true)
        XCTAssertEqual(restoreCalls, 1)
    }

    @MainActor
    func testDetachingNativeControllerForStagingSurfaceClearsDelegateAndPiP() {
        let engine = AVPlayerHLSBridgeEngine()
        let player = PlayerStateViewModel(
            videoURL: URL(string: "https://example.com/v.m4s"),
            audioURL: URL(string: "https://example.com/a.m4s"),
            title: "Detach Native PiP Cleanup",
            referer: "https://www.bilibili.com",
            engine: engine
        )
        let surfaceHost = DirectUIKitPlayerSurfaceHostView(
            viewModel: player,
            isPictureInPictureEnabled: true,
            allowsAutomaticPictureInPictureFromInline: false,
            prefersNativePlaybackSurface: true,
            showsNativePlaybackControls: true,
            showsNativePlaybackSpeeds: true,
            enablesNativeSurfaceGestures: false,
            nativeAllowsPictureInPicturePlayback: nil
        )
        defer {
            surfaceHost.tearDown()
            player.stop()
        }

        let nativeVC = surfaceHost.nativePlayerViewController
        XCTAssertTrue(nativeVC.delegate === player)

        let stagingContainer = VideoSurfaceContainerView()
        stagingContainer.setPictureInPictureEnabled(true)
        stagingContainer.setPlayerViewModel(player, prefersNativePlaybackControls: false)
        player.attachSurface(stagingContainer, prefersNativePlaybackControls: false)
        XCTAssertNil(nativeVC.delegate)
        XCTAssertFalse(nativeVC.allowsPictureInPicturePlayback)
    }

    @MainActor
    func testTransferredMiniPlayerClearsSurfaceModelAndIgnoresLateShellHostCreation() async throws {
        libraryStore.setAutoPictureInPictureOnExitEnabled(true)
        let localVideoURL = try await makeLocalTestVideoURL()
        defer { try? FileManager.default.removeItem(at: localVideoURL) }

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 430, height: 932)
        let rootVC = UIViewController()
        window.rootViewController = rootVC
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }

        let engine = AVPlayerHLSBridgeEngine()
        let player = PlayerStateViewModel(
            videoURL: localVideoURL,
            audioURL: nil,
            title: "Transferred Surface Guard",
            referer: "https://www.bilibili.com",
            durationHint: 4,
            engine: engine
        )
        let dependencies = AppDependencies()
        let prevAutoExit = dependencies.libraryStore.autoPictureInPictureOnExitEnabled
        let prevPiP = dependencies.libraryStore.pictureInPictureEnabled
        dependencies.libraryStore.setAutoPictureInPictureOnExitEnabled(true)
        dependencies.libraryStore.setPictureInPictureEnabled(false)
        defer {
            dependencies.libraryStore.setAutoPictureInPictureOnExitEnabled(prevAutoExit)
            dependencies.libraryStore.setPictureInPictureEnabled(prevPiP)
        }
        let video = makeVideo(bvid: "BV1LateShellGuard", cid: 902)
        let detailVM = VideoDetailViewModel(
            seedVideo: video,
            api: dependencies.api,
            libraryStore: dependencies.libraryStore,
            sessionStore: dependencies.sessionStore,
            sponsorBlockService: SponsorBlockService()
        )
        let variant = PlayVariant(
            quality: 80, title: "1080P", videoURL: localVideoURL,
            audioURL: nil, videoStream: nil, audioStream: nil,
            codec: "AVC", resolution: nil, frameRate: "15", bandwidth: 2_000_000, isHDR: false, badge: nil
        )
        detailVM.playVariants = [variant]
        detailVM.selectedPlayVariant = variant
        detailVM.state = .loaded
        detailVM.playURLState = .loaded
        detailVM.installStablePlayerViewModel(
            player,
            variant: variant,
            resumeCandidate: PlaybackResumeCandidate(time: 0, sourceTitle: "test", reason: "test", cid: 902),
            resumeTime: 0,
            playbackRate: .x10,
            shouldAutoplay: true,
            playbackHandoffSource: nil
        )
        detailVM.playerWindowFrameProvider = {
            (CGRect(x: 0, y: 59, width: 430, height: 242), window)
        }

        let initialSurface = VideoSurfaceContainerView(frame: CGRect(x: 0, y: 0, width: 430, height: 242))
        player.attachSurface(initialSurface, prefersNativePlaybackControls: true)
        try await engine.prepare(source: PlayerStreamSource(
            metricsID: video.bvid,
            videoURL: localVideoURL,
            audioURL: nil,
            videoStream: nil,
            audioStream: nil,
            alternateVideoRenditions: [],
            referer: "https://www.bilibili.com/video/\(video.bvid)",
            httpHeaders: [:],
            title: video.title,
            durationHint: 4,
            isLiveStream: false,
            isLiveHLS: false,
            liveHLSFormat: nil,
            resumeTime: 0,
            dynamicRange: .sdr,
            cdnPreference: .automatic
        ))
        player.play()
        for _ in 0..<80 {
            if player.isPlaying && player.hasPresentedPlayback { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(player.isPlaying)
        XCTAssertTrue(player.hasPresentedPlayback)

        let containerModel = VideoDetailSwiftUIContainerModel(
            viewModel: detailVM,
            initialVideo: video,
            runtimeSettings: VideoDetailRuntimeSettingsStore(),
            rotationCoordinator: PlaybackRotationCoordinator(),
            initialContentTab: .detail
        )
        XCTAssertTrue(containerModel.surfacePlayerViewModel === player)
        XCTAssertFalse(containerModel.isTransferredToSystemMiniPlayer)

        let coordinator = SystemMiniPlayerCoordinator.shared
        coordinator.supportsPictureInPicture = { true }
        coordinator.onStartPictureInPicture = { _, _ in }

        detailVM.markExitingVideoDetailRoute()
        XCTAssertTrue(detailVM.handoffToSystemMiniPlayerIfEligible())
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertNil(containerModel.surfacePlayerViewModel)
        XCTAssertTrue(containerModel.isTransferredToSystemMiniPlayer)
        let stagingHost = try XCTUnwrap(window.subviews.compactMap { $0 as? SystemMiniPlayerStagingView }.first)
        XCTAssertTrue(stagingHost.surfaceView.isBound(to: player))
        XCTAssertFalse(player.usesNativePlaybackSurfaceController)

        // Even if SwiftUI constructs or mutates a VideoDetailShellSurfaceHost after handoff,
        // it must never rebind `AVPlayer` away from SystemMiniPlayerStagingView.
        let lateHost = VideoDetailShellSurfaceHost(
            playerViewModel: player,
            detailViewModel: detailVM,
            dependencies: dependencies,
            runtimeSettings: VideoDetailRuntimeSettingsStore(),
            rotationCoordinator: PlaybackRotationCoordinator(),
            onShowMoreControls: { $0() },
            onDismissMoreControls: {},
            onRequestFullscreen: {},
            onExitFullscreen: {},
            onToggleDanmaku: {},
            onShowDanmakuSettings: {}
        )
        defer {
            lateHost.tearDown()
            coordinator.resetForTesting()
            player.stop()
        }
        lateHost.attach(to: rootVC)
        lateHost.setPlayerViewModel(player)
        lateHost.setVideoGravity(.resizeAspectFill)
        lateHost.refreshLayoutImmediately()
        dependencies.libraryStore.setPictureInPictureEnabled(!dependencies.libraryStore.pictureInPictureEnabled)
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(lateHost.isTransferredToSystemMiniPlayer)
        XCTAssertTrue(stagingHost.surfaceView.isBound(to: player))
        XCTAssertFalse(player.usesNativePlaybackSurfaceController)
        XCTAssertTrue(
            stagingHost.surfaceView.drawableView.layer.sublayers?.contains(where: { $0 is AVPlayerLayer }) == true
        )
    }

    func testOpeningNewVideoStopsPreviousMiniPlayerDetachesStagingAndIgnoresLatePiPSceneBackground() {
        let coordinator = SystemMiniPlayerCoordinator.shared
        coordinator.resetForTesting()
        defer { coordinator.resetForTesting() }
        ActivePlaybackCoordinator.shared.stopActivePlayback()
        defer { ActivePlaybackCoordinator.shared.stopActivePlayback() }

        coordinator.supportsPictureInPicture = { true }
        let videoA = makeVideo(bvid: "BV1PiPOldVideoA", cid: 1001)
        let videoB = makeVideo(bvid: "BV1PiPNewVideoB", cid: 2002)
        let (detailVMA, engineA, playerA) = makePlayingDetailViewModel(video: videoA)
        defer {
            _ = detailVMA
            playerA.stop()
        }

        let stagingHost = SystemMiniPlayerStagingView()
        let api = BiliAPIClient(
            sessionStore: SessionStore(),
            libraryStore: LibraryStore(),
            homeRecommendDiagnosticsStore: .shared
        )
        coordinator.onAttachStagingSurface = { _, player, _, _ in
            stagingHost.surfaceView.setPlayerViewModel(player, prefersNativePlaybackControls: false)
            player.attachSurface(
                stagingHost.surfaceView,
                prefersNativePlaybackControls: false,
                preservesReadinessDuringSurfaceHandoff: true
            )
        }
        coordinator.onStartPictureInPicture = { player, _ in
            engineA.isPictureInPictureActive = true
            player.onPictureInPictureDidStart?()
        }

        XCTAssertTrue(
            coordinator.beginMiniPlayer(
                with: SystemMiniPlayerCoordinator.RetainedSession(
                    video: videoA,
                    selectedCID: videoA.cid,
                    playVariants: [],
                    selectedPlayVariant: nil,
                    currentPlayURLData: nil,
                    isDanmakuEnabled: true,
                    hasResolvedDetailMetadata: true,
                    stablePlayerIdentity: videoA.bvid,
                    playerViewModel: playerA,
                    recordsPlaybackHistory: false,
                    api: api,
                    libraryStore: LibraryStore()
                )
            )
        )
        XCTAssertTrue(engineA.isPictureInPictureActive)
        XCTAssertTrue(stagingHost.surfaceView.isBound(to: playerA))

        coordinator.prepareForOpeningVideo(videoB)
        XCTAssertNil(coordinator.activeSession)
        XCTAssertTrue(playerA.isTerminated)
        XCTAssertEqual(engineA.stopCallCount, 1)
        XCTAssertFalse(engineA.isPictureInPictureActive)
        XCTAssertFalse(stagingHost.surfaceView.isBound(to: playerA))

        let (detailVMB, engineB, playerB) = makePlayingDetailViewModel(video: videoB)
        defer {
            _ = detailVMB
            playerB.stop()
        }
        let surfaceB = VideoSurfaceContainerView()
        playerB.attachSurface(surfaceB, prefersNativePlaybackControls: false)
        ActivePlaybackCoordinator.shared.activate(playerB)
        playerB.play()

        let appDelegate = AppDelegate()
        XCTAssertFalse(
            appDelegate.handleSceneDidEnterBackground(
                Notification(name: UIScene.didEnterBackgroundNotification, object: NSObject())
            )
        )
        XCTAssertTrue(playerB.wantsAutoplay)
        XCTAssertTrue(engineB.isPlaying)
        XCTAssertEqual(engineB.pauseCallCount, 0)
        XCTAssertFalse(playerB.isAwaitingAppBackgroundSurfaceRecovery)
    }

    func testOpeningNewVideoDefersLayerTeardownUntilAsyncPiPDidStop() {
        let coordinator = SystemMiniPlayerCoordinator.shared
        coordinator.resetForTesting()
        defer { coordinator.resetForTesting() }
        ActivePlaybackCoordinator.shared.stopActivePlayback()
        defer { ActivePlaybackCoordinator.shared.stopActivePlayback() }

        coordinator.supportsPictureInPicture = { true }
        let videoA = makeVideo(bvid: "BV1AsyncPiPOldA", cid: 3001)
        let videoB = makeVideo(bvid: "BV1AsyncPiPNewB", cid: 3002)
        let (detailVMA, engineA, playerA) = makePlayingDetailViewModel(video: videoA)
        engineA.keepsPictureInPictureActiveOnStopRequest = true
        defer {
            _ = detailVMA
            playerA.stop()
        }

        let stagingHost = SystemMiniPlayerStagingView()
        let api = BiliAPIClient(
            sessionStore: SessionStore(),
            libraryStore: LibraryStore(),
            homeRecommendDiagnosticsStore: .shared
        )
        coordinator.onAttachStagingSurface = { _, player, _, _ in
            stagingHost.surfaceView.setPlayerViewModel(player, prefersNativePlaybackControls: false)
            player.attachSurface(
                stagingHost.surfaceView,
                prefersNativePlaybackControls: false,
                preservesReadinessDuringSurfaceHandoff: true
            )
        }
        coordinator.onStartPictureInPicture = { player, _ in
            engineA.isPictureInPictureActive = true
            player.onPictureInPictureDidStart?()
        }

        XCTAssertTrue(
            coordinator.beginMiniPlayer(
                with: SystemMiniPlayerCoordinator.RetainedSession(
                    video: videoA,
                    selectedCID: videoA.cid,
                    playVariants: [],
                    selectedPlayVariant: nil,
                    currentPlayURLData: nil,
                    isDanmakuEnabled: true,
                    hasResolvedDetailMetadata: true,
                    stablePlayerIdentity: videoA.bvid,
                    playerViewModel: playerA,
                    recordsPlaybackHistory: false,
                    api: api,
                    libraryStore: LibraryStore()
                )
            )
        )
        ActivePlaybackCoordinator.shared.activate(playerA)

        coordinator.prepareForOpeningVideo(videoB)
        XCTAssertNil(coordinator.activeSession)
        XCTAssertFalse(ActivePlaybackCoordinator.shared.isActive(playerA))
        XCTAssertFalse(playerA.isTerminated)
        XCTAssertEqual(engineA.pauseCallCount, 1)
        XCTAssertEqual(engineA.stopCallCount, 0)
        XCTAssertTrue(stagingHost.surfaceView.isBound(to: playerA))

        engineA.isPictureInPictureActive = false
        playerA.onPictureInPictureDidStop?()

        XCTAssertTrue(playerA.isTerminated)
        XCTAssertEqual(engineA.stopCallCount, 1)
        XCTAssertFalse(stagingHost.surfaceView.isBound(to: playerA))
    }

    func testExternalPauseDuringActivePiPSyncsPausedIntentWithoutAutoResuming() async throws {
        XCTAssertTrue(
            AVPlayerHLSBridgeEngine.shouldTreatExternalPauseAsPausedIntent(
                wantsPlayback: true,
                hasObservedActivePlayback: true,
                isPerformingSeek: false,
                isAwaitingAudioSessionActivation: false,
                isAudioSessionDeactivating: false,
                lastPlaybackState: .playing,
                itemStatus: .readyToPlay
            )
        )
        XCTAssertFalse(
            AVPlayerHLSBridgeEngine.shouldTreatExternalPauseAsPausedIntent(
                wantsPlayback: true,
                hasObservedActivePlayback: false,
                isPerformingSeek: false,
                isAwaitingAudioSessionActivation: false,
                isAudioSessionDeactivating: false,
                lastPlaybackState: .buffering,
                itemStatus: .readyToPlay
            )
        )
        XCTAssertFalse(
            AVPlayerHLSBridgeEngine.shouldTreatExternalPauseAsPausedIntent(
                wantsPlayback: true,
                hasObservedActivePlayback: true,
                isPerformingSeek: true,
                isAwaitingAudioSessionActivation: false,
                isAudioSessionDeactivating: false,
                lastPlaybackState: .playing,
                itemStatus: .readyToPlay
            )
        )

        ActivePlaybackCoordinator.shared.stopActivePlayback()
        defer { ActivePlaybackCoordinator.shared.stopActivePlayback() }

        let video = makeVideo(bvid: "BV1PiPPauseSync", cid: 4001)
        let (detailVM, engine, player) = makePlayingDetailViewModel(video: video)
        defer {
            _ = detailVM
            player.stop()
        }
        let surface = VideoSurfaceContainerView()
        player.attachSurface(surface, prefersNativePlaybackControls: false)
        ActivePlaybackCoordinator.shared.activate(player)
        player.play()
        engine.isPictureInPictureActive = true

        let playCountBeforePiPPause = engine.playCallCount
        engine.simulateExternalPause()

        XCTAssertFalse(player.wantsAutoplay)
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.playbackPhase, .paused)

        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(engine.playCallCount, playCountBeforePiPPause)
        XCTAssertFalse(player.wantsAutoplay)
        XCTAssertFalse(player.isPlaying)

        player.play()
        XCTAssertTrue(player.wantsAutoplay)
        player.beginSurfaceMigrationHold()
        engine.simulateExternalPause()
        XCTAssertTrue(player.wantsAutoplay)
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
    private(set) var playCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var pauseCallCount = 0
    var playbackErrorMessage: String? { nil }
    var needsMediaRecovery: Bool { false }
    var lastFailureReason: HLSBridgeFailureReason? { nil }
    var supportsPictureInPicture: Bool { true }
    var isPictureInPictureActive = false
    var keepsPictureInPictureActiveOnStopRequest = false
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
        playCallCount += 1
        isPlaying = true
        onPlaybackIntentChange?(true)
        onPlaybackStateChange?(.playing)
        onFirstFrame?(12)
    }

    func simulateExternalPause() {
        isPlaying = false
        onPlaybackIntentChange?(false)
        onPlaybackStateChange?(.paused)
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
    func stopPictureInPictureIfNeeded() {
        if !keepsPictureInPictureActiveOnStopRequest {
            isPictureInPictureActive = false
        }
    }
    func invalidatePictureInPicturePlaybackState() {}
}
