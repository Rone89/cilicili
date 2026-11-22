import AVFoundation
import SwiftUI
import UIKit
import XCTest
@testable import bili

@MainActor
final class AdaptiveLayoutAndPlayerIdentityTests: XCTestCase {
    func testAdaptiveLayoutPolicyBreakpointsAndExperimentFallback() {
        XCTAssertEqual(
            AdaptiveLayoutPolicy.widthTier(containerSize: CGSize(width: 390, height: 844), horizontalSizeClass: .compact),
            .compact
        )
        XCTAssertEqual(
            AdaptiveLayoutPolicy.widthTier(containerSize: CGSize(width: 956, height: 440), horizontalSizeClass: .compact),
            .compact
        )
        XCTAssertEqual(
            AdaptiveLayoutPolicy.widthTier(containerSize: CGSize(width: 680, height: 800), horizontalSizeClass: .regular),
            .medium
        )
        XCTAssertEqual(
            AdaptiveLayoutPolicy.widthTier(containerSize: CGSize(width: 1024, height: 1366), horizontalSizeClass: .regular),
            .expanded
        )
        XCTAssertEqual(
            AdaptiveLayoutPolicy.widthTier(containerSize: CGSize(width: 1366, height: 1024), horizontalSizeClass: .regular),
            .wide
        )
        XCTAssertEqual(
            AdaptiveLayoutPolicy.widthTier(
                containerSize: CGSize(width: 1366, height: 1024),
                horizontalSizeClass: .regular,
                adaptiveEnabled: false
            ),
            .compact
        )
    }

    func testHomeFeedLayoutMetricsAdaptsColumnsWithoutAffectingCompact() {
        let compact = HomeFeedLayoutMetrics(
            mode: .doubleColumn,
            containerWidth: 390,
            viewportHeight: 844,
            horizontalSizeClass: .compact,
            adaptiveLargeScreenEnabled: true
        )
        XCTAssertEqual(compact.doubleColumns.count, 2)
        XCTAssertEqual(compact.feedHorizontalPadding, 20)
        XCTAssertNil(compact.maxContentWidth)

        let duoUnfolded = HomeFeedLayoutMetrics(
            mode: .doubleColumn,
            containerWidth: 744,
            viewportHeight: 1133,
            horizontalSizeClass: .regular,
            adaptiveLargeScreenEnabled: true
        )
        XCTAssertEqual(duoUnfolded.doubleColumns.count, 3)
        XCTAssertEqual(duoUnfolded.feedHorizontalPadding, 24)

        let ipadLandscape = HomeFeedLayoutMetrics(
            mode: .doubleColumn,
            containerWidth: 1366,
            viewportHeight: 1024,
            horizontalSizeClass: .regular,
            adaptiveLargeScreenEnabled: true
        )
        XCTAssertEqual(ipadLandscape.doubleColumns.count, 5)
        XCTAssertEqual(ipadLandscape.feedHorizontalPadding, 32)
        XCTAssertEqual(ipadLandscape.maxContentWidth, AdaptiveLayoutPolicy.multiColumnFeedMaxWidth)

        let disabled = HomeFeedLayoutMetrics(
            mode: .doubleColumn,
            containerWidth: 1366,
            viewportHeight: 1024,
            horizontalSizeClass: .regular,
            adaptiveLargeScreenEnabled: false
        )
        XCTAssertEqual(disabled.doubleColumns.count, 2)
    }

    func testVideoDetailShellLayoutResolvesTwoColumnSplitAndRevertsToCompact() {
        let compact = VideoDetailShellLayout.resolve(
            bounds: CGRect(x: 0, y: 0, width: 390, height: 844),
            safeAreaTop: 59,
            safeAreaBottom: 34,
            videoAspectRatio: 16.0 / 9.0,
            currentPlayerHeight: nil,
            isPlaybackActive: true,
            isLandscape: false,
            isPortraitFullscreen: false,
            horizontalSizeClass: .compact,
            adaptiveLargeScreenEnabled: true
        )
        XCTAssertEqual(compact.adaptiveMode, .compactStacked)
        XCTAssertEqual(compact.playerFrame.width, 390)
        XCTAssertEqual(compact.contentFrame.minX, 0)
        XCTAssertGreaterThan(compact.contentTopInset ?? 0, 200)

        let ipadPortrait = VideoDetailShellLayout.resolve(
            bounds: CGRect(x: 0, y: 0, width: 1024, height: 1366),
            safeAreaTop: 24,
            safeAreaBottom: 20,
            videoAspectRatio: 16.0 / 9.0,
            currentPlayerHeight: nil,
            isPlaybackActive: true,
            isLandscape: false,
            isPortraitFullscreen: false,
            horizontalSizeClass: .regular,
            adaptiveLargeScreenEnabled: true
        )
        XCTAssertEqual(ipadPortrait.adaptiveMode, .compactStacked)
        XCTAssertEqual(ipadPortrait.playerFrame.width, 1024)

        let split = VideoDetailShellLayout.resolve(
            bounds: CGRect(x: 0, y: 0, width: 1366, height: 1024),
            safeAreaTop: 24,
            safeAreaBottom: 20,
            videoAspectRatio: 16.0 / 9.0,
            currentPlayerHeight: nil,
            isPlaybackActive: true,
            isLandscape: false,
            isPortraitFullscreen: false,
            horizontalSizeClass: .regular,
            adaptiveLargeScreenEnabled: true
        )
        XCTAssertEqual(split.adaptiveMode, .twoColumnSplit)
        XCTAssertFalse(split.usesFullscreenLayout)
        XCTAssertEqual(split.contentTopInset, 0)
        XCTAssertEqual(split.contentFrame.minY, 0)
        XCTAssertEqual(split.contentFrame.height, 1024)
        XCTAssertEqual(split.playerFrame.minX, 0)
        XCTAssertGreaterThanOrEqual(split.playerFrame.width, 800)
        XCTAssertEqual(split.contentFrame.minX, split.playerFrame.width, accuracy: 0.5)
        XCTAssertEqual(split.contentFrame.width, 460, accuracy: 0.5)
        XCTAssertEqual(split.danmakuCanvasSize, split.playerFrame.size)

        let duoInnerLandscape = VideoDetailShellLayout.resolve(
            bounds: CGRect(x: 0, y: 0, width: 951, height: 669),
            safeAreaTop: 0,
            safeAreaBottom: 20,
            videoAspectRatio: 16.0 / 9.0,
            currentPlayerHeight: nil,
            isPlaybackActive: true,
            isLandscape: false,
            isPortraitFullscreen: false,
            horizontalSizeClass: .regular,
            adaptiveLargeScreenEnabled: true
        )
        XCTAssertEqual(duoInnerLandscape.adaptiveMode, .twoColumnSplit)
        XCTAssertEqual(duoInnerLandscape.contentFrame.minY, 0)
        XCTAssertEqual(duoInnerLandscape.contentFrame.height, 669)
        XCTAssertEqual(duoInnerLandscape.contentFrame.width, 380, accuracy: 0.5)

        let narrowSplit = VideoDetailShellLayout.resolve(
            bounds: CGRect(x: 0, y: 0, width: 500, height: 1024),
            safeAreaTop: 24,
            safeAreaBottom: 20,
            videoAspectRatio: 16.0 / 9.0,
            currentPlayerHeight: nil,
            isPlaybackActive: true,
            isLandscape: false,
            isPortraitFullscreen: false,
            horizontalSizeClass: .compact,
            adaptiveLargeScreenEnabled: true
        )
        XCTAssertEqual(narrowSplit.adaptiveMode, .compactStacked)
    }

    func testVideoDetailContainerPreservesPlayerAndSurfaceIdentityAcrossContinuousResizing() async throws {
        let mediaURL = try await makeLocalTestVideo()
        defer { try? FileManager.default.removeItem(at: mediaURL) }

        let dependencies = AppDependencies()
        let previousAdaptive = dependencies.libraryStore.adaptiveLargeScreenLayoutExperimentEnabled
        dependencies.libraryStore.setAdaptiveLargeScreenLayoutExperimentEnabled(true)
        defer { dependencies.libraryStore.setAdaptiveLargeScreenLayoutExperimentEnabled(previousAdaptive) }

        let video = try JSONDecoder.bili.decode(VideoItem.self, from: Data("""
            {"bvid":"BVAdaptiveIdentityProbe","title":"Adaptive identity probe","cid":101,"dimension":{"width":1920,"height":1080,"rotate":0}}
            """.utf8))
        let detailVM = VideoDetailViewModel(
            seedVideo: video,
            api: dependencies.api,
            libraryStore: dependencies.libraryStore,
            sessionStore: dependencies.sessionStore,
            sponsorBlockService: dependencies.sponsorBlockService
        )

        let engine = AVPlayerHLSBridgeEngine()
        let playerVM = PlayerStateViewModel(
            videoURL: mediaURL,
            audioURL: nil,
            title: video.title,
            referer: "https://www.bilibili.com",
            engine: engine
        )
        let variant = PlayVariant(
            quality: 80,
            title: "1080P",
            videoURL: mediaURL,
            audioURL: nil,
            videoStream: nil,
            audioStream: nil,
            codec: "AVC",
            resolution: nil,
            frameRate: "24",
            bandwidth: 2_000_000,
            isHDR: false,
            badge: nil
        )
        detailVM.playVariants = [variant]
        detailVM.selectedPlayVariant = variant
        detailVM.state = .loaded
        detailVM.playURLState = .loaded
        detailVM.installStablePlayerViewModel(
            playerVM,
            variant: variant,
            resumeCandidate: PlaybackResumeCandidate(time: 0, sourceTitle: "test", reason: "test", cid: 101),
            resumeTime: 0,
            playbackRate: .x10,
            shouldAutoplay: true,
            playbackHandoffSource: nil
        )

        try await engine.prepare(source: PlayerStreamSource(
            metricsID: UUID().uuidString,
            videoURL: mediaURL,
            audioURL: nil,
            videoStream: nil,
            audioStream: nil,
            alternateVideoRenditions: [],
            referer: "https://www.bilibili.com",
            httpHeaders: [:],
            title: video.title,
            durationHint: 12,
            isLiveStream: false,
            isLiveHLS: false,
            liveHLSFormat: nil,
            resumeTime: 0,
            dynamicRange: .sdr,
            cdnPreference: .automatic
        ))
        playerVM.play()

        let runtime = VideoDetailRuntimeSettingsStore()
        runtime.bind(dependencies.libraryStore)
        let coordinator = PlaybackRotationCoordinator()
        let containerModel = VideoDetailSwiftUIContainerModel(
            viewModel: detailVM,
            initialVideo: video,
            runtimeSettings: runtime,
            rotationCoordinator: coordinator,
            initialContentTab: .detail
        )

        let root = VideoDetailSwiftUIContainer(
            viewModel: detailVM,
            model: containerModel,
            runtimeSettings: runtime,
            rotationCoordinator: coordinator,
            selectedContentTab: .constant(.detail),
            dependencies: dependencies,
            onShowNetworkDiagnostics: {},
            onShowFavoriteFolders: {},
            onShowCoinPicker: {},
            onOpenCommentComposer: { _ in },
            onReply: { _ in },
            openVideoOwnerRoute: nil,
            onShowMoreControls: { _ in },
            onDismissMoreControls: {},
            onRequestFullscreen: { coordinator.setInPlaceFullscreen(true) },
            onExitFullscreen: { coordinator.setInPlaceFullscreen(false) },
            onToggleDanmaku: {},
            onShowDanmakuSettings: {},
            onNavigateBack: {}
        )

        let controller = UIHostingController(
            rootView: root
                .environmentObject(dependencies)
                .environmentObject(dependencies.libraryStore)
                .environmentObject(dependencies.sessionStore)
        )
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKey = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKey?.makeKey()
            playerVM.stop()
        }

        let initialSurfaceHost = try await waitForSurfaceHost(in: window)
        for _ in 0..<40 {
            if playerVM.isPlaying { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(playerVM.isPlaying)
        let initialSurfaceHostID = ObjectIdentifier(initialSurfaceHost)
        let initialPlayerVMID = ObjectIdentifier(playerVM)
        let initialAVPlayerID = try XCTUnwrap(playerVM.debugAVPlayerIdentity)
        let initialAVPlayerItemID = try XCTUnwrap(playerVM.debugAVPlayerItemIdentity)

        let sizes: [(CGSize, Bool)] = [
            (CGSize(width: 680, height: 800), false),   // Duo unfolded narrow portrait
            (CGSize(width: 780, height: 760), false),   // Duo unfolded wide split
            (CGSize(width: 1024, height: 1366), false), // iPad 13" portrait split
            (CGSize(width: 1366, height: 1024), false), // iPad 13" landscape split
            (CGSize(width: 1366, height: 1024), true),  // iPad in-place fullscreen
            (CGSize(width: 1366, height: 1024), false), // Exit fullscreen back to split
            (CGSize(width: 400, height: 1024), false),  // Narrow Slide Over / Duo cover
            (CGSize(width: 834, height: 1194), false),  // Re-expand to split
        ]

        for (index, entry) in sizes.enumerated() {
            if index == 2 {
                _ = engine.seek(toTime: 4)
            } else if index == 4 {
                playerVM.pause()
            } else if index == 6 {
                playerVM.play()
            }
            window.frame = CGRect(origin: .zero, size: entry.0)
            coordinator.setInPlaceFullscreen(entry.1)
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(80))

            let currentSurfaceHost = try XCTUnwrap(findSurfaceHost(in: window))
            XCTAssertEqual(ObjectIdentifier(currentSurfaceHost), initialSurfaceHostID, "Surface host recreated at step \(index) size=\(entry.0)")
            XCTAssertEqual(ObjectIdentifier(try XCTUnwrap(containerModel.surfacePlayerViewModel)), initialPlayerVMID)
            XCTAssertEqual(playerVM.debugAVPlayerIdentity, initialAVPlayerID, "AVPlayer recreated at step \(index)")
            XCTAssertEqual(playerVM.debugAVPlayerItemIdentity, initialAVPlayerItemID, "AVPlayerItem recreated at step \(index)")
            if index == 4 || index == 5 {
                XCTAssertFalse(playerVM.isPlaying, "Paused intent should stay paused across layout change at step \(index)")
            } else {
                if index == 6 {
                    for _ in 0..<20 {
                        if playerVM.isPlaying { break }
                        try await Task.sleep(for: .milliseconds(25))
                    }
                }
                XCTAssertTrue(playerVM.isPlaying, "Playing intent should remain active at step \(index)")
            }
        }
    }

    func testOrientationLockAllowsLandscapeOnRegularOrPadWindowAndLocksCompactPhone() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let compactWindow = UIWindow(windowScene: scene)
        compactWindow.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        compactWindow.traitOverrides.horizontalSizeClass = .compact
        compactWindow.traitOverrides.userInterfaceIdiom = .phone
        XCTAssertFalse(AdaptiveLayoutPolicy.allowsUnrestrictedRootOrientation(for: compactWindow))
        XCTAssertEqual(AppOrientationLock.resolvedSupportedOrientations(for: compactWindow), .portrait)

        let regularPhoneWindow = UIWindow(windowScene: scene)
        regularPhoneWindow.frame = CGRect(x: 0, y: 0, width: 780, height: 760)
        regularPhoneWindow.traitOverrides.horizontalSizeClass = .regular
        regularPhoneWindow.traitOverrides.userInterfaceIdiom = .phone
        XCTAssertTrue(AdaptiveLayoutPolicy.allowsUnrestrictedRootOrientation(for: regularPhoneWindow))
        XCTAssertEqual(AppOrientationLock.resolvedSupportedOrientations(for: regularPhoneWindow), .allButUpsideDown)

        let landscapeMaxPhoneWindow = UIWindow(windowScene: scene)
        landscapeMaxPhoneWindow.frame = CGRect(x: 0, y: 0, width: 956, height: 440)
        landscapeMaxPhoneWindow.traitOverrides.horizontalSizeClass = .regular
        landscapeMaxPhoneWindow.traitOverrides.verticalSizeClass = .compact
        landscapeMaxPhoneWindow.traitOverrides.userInterfaceIdiom = .phone
        XCTAssertFalse(AdaptiveLayoutPolicy.allowsUnrestrictedRootOrientation(for: landscapeMaxPhoneWindow))
        XCTAssertEqual(AppOrientationLock.resolvedSupportedOrientations(for: landscapeMaxPhoneWindow), .portrait)

        let padWindow = UIWindow(windowScene: scene)
        padWindow.frame = CGRect(x: 0, y: 0, width: 1024, height: 1366)
        padWindow.traitOverrides.horizontalSizeClass = .regular
        padWindow.traitOverrides.userInterfaceIdiom = .pad
        XCTAssertTrue(AdaptiveLayoutPolicy.allowsUnrestrictedRootOrientation(for: padWindow))
        XCTAssertEqual(AppOrientationLock.resolvedSupportedOrientations(for: padWindow), .all)
    }

    func testVerticalTrailingChromeRailDetectsDuoCoverPortraitOnly() {
        // iPhone Duo cover display (portrait)
        XCTAssertTrue(
            AdaptiveLayoutPolicy.usesVerticalTrailingChromeRail(
                containerSize: CGSize(width: 466, height: 678),
                safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 34, trailing: 84)
            )
        )
        // iPhone Duo unfolded inner display (landscape uses twoColumnSplit with right-column horizontal toolbar)
        XCTAssertFalse(
            AdaptiveLayoutPolicy.usesVerticalTrailingChromeRail(
                containerSize: CGSize(width: 951, height: 669),
                safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 20, trailing: 84)
            )
        )
        // Standard iPhone portrait
        XCTAssertFalse(
            AdaptiveLayoutPolicy.usesVerticalTrailingChromeRail(
                containerSize: CGSize(width: 440, height: 956),
                safeAreaInsets: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0)
            )
        )
        // iPhone Duo unfolded inner display (portrait)
        XCTAssertFalse(
            AdaptiveLayoutPolicy.usesVerticalTrailingChromeRail(
                containerSize: CGSize(width: 669, height: 951),
                safeAreaInsets: EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0)
            )
        )
        // Standard iPhone landscape (symmetric horizontal safe areas)
        XCTAssertFalse(
            AdaptiveLayoutPolicy.usesVerticalTrailingChromeRail(
                containerSize: CGSize(width: 956, height: 440),
                safeAreaInsets: EdgeInsets(top: 0, leading: 62, bottom: 21, trailing: 62)
            )
        )
        // iPad landscape
        XCTAssertFalse(
            AdaptiveLayoutPolicy.usesVerticalTrailingChromeRail(
                containerSize: CGSize(width: 1366, height: 1024),
                safeAreaInsets: EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0)
            )
        )
    }

    func testIsDuoUnfoldedInnerDisplayDetectsUnfoldedPhoneOnly() {
        XCTAssertTrue(
            AdaptiveLayoutPolicy.isDuoUnfoldedInnerDisplay(
                containerSize: CGSize(width: 669, height: 951),
                userInterfaceIdiom: .phone
            )
        )
        XCTAssertTrue(
            AdaptiveLayoutPolicy.isDuoUnfoldedInnerDisplay(
                containerSize: CGSize(width: 951, height: 669),
                userInterfaceIdiom: .phone
            )
        )
        XCTAssertFalse(
            AdaptiveLayoutPolicy.isDuoUnfoldedInnerDisplay(
                containerSize: CGSize(width: 466, height: 678),
                userInterfaceIdiom: .phone
            )
        )
        XCTAssertFalse(
            AdaptiveLayoutPolicy.isDuoUnfoldedInnerDisplay(
                containerSize: CGSize(width: 440, height: 956),
                userInterfaceIdiom: .phone
            )
        )
        XCTAssertFalse(
            AdaptiveLayoutPolicy.isDuoUnfoldedInnerDisplay(
                containerSize: CGSize(width: 956, height: 440),
                userInterfaceIdiom: .phone
            )
        )
        XCTAssertFalse(
            AdaptiveLayoutPolicy.isDuoUnfoldedInnerDisplay(
                containerSize: CGSize(width: 1024, height: 1366),
                userInterfaceIdiom: .pad
            )
        )
        XCTAssertFalse(
            AdaptiveLayoutPolicy.isDuoUnfoldedInnerDisplay(
                containerSize: CGSize(width: 1366, height: 1024),
                userInterfaceIdiom: .pad
            )
        )
    }

    private func waitForSurfaceHost(in root: UIView) async throws -> DirectUIKitPlayerSurfaceHostView {
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            if let found = findSurfaceHost(in: root) {
                return found
            }
            try await Task.sleep(for: .milliseconds(30))
        }
        return try XCTUnwrap(findSurfaceHost(in: root))
    }

    private func findSurfaceHost(in view: UIView) -> DirectUIKitPlayerSurfaceHostView? {
        if let host = view as? DirectUIKitPlayerSurfaceHostView {
            return host
        }
        for subview in view.subviews {
            if let found = findSurfaceHost(in: subview) {
                return found
            }
        }
        return nil
    }

    private func makeLocalTestVideo() async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("adaptive-layout-probe-\(UUID().uuidString).mov")
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

        for index in 0...20 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            var buffer: CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferPoolCreatePixelBuffer(nil, try XCTUnwrap(adaptor.pixelBufferPool), &buffer), kCVReturnSuccess)
            let pixelBuffer = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            XCTAssertTrue(adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: Int64(index), timescale: 1)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        return url
    }
}
