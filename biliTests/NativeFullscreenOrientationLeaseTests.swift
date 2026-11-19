import AVFoundation
import AVKit
import Combine
import SwiftUI
import UIKit
import XCTest
@testable import bili

@MainActor
final class NativeFullscreenOrientationLeaseTests: XCTestCase {
    override func tearDown() {
        MainActor.assumeIsolated {
            NativeFullscreenOrientationLease.shared.cancel()
            AppOrientationLock.restorePortrait()
        }
        super.tearDown()
    }

    func testFullscreenTargetOrientationFollowsContentAspect() {
        XCTAssertEqual(
            NativeFullscreenOrientationLease.fullscreenTargetOrientation(
                presentationSize: CGSize(width: 1920, height: 1080)
            ),
            .landscapeRight
        )
        XCTAssertEqual(
            NativeFullscreenOrientationLease.fullscreenTargetOrientation(
                presentationSize: CGSize(width: 1080, height: 1920)
            ),
            .portrait
        )
    }

    func testFullscreenTargetOrientationFallsBackToLandscapeWhenUnknown() {
        XCTAssertEqual(
            NativeFullscreenOrientationLease.fullscreenTargetOrientation(presentationSize: .zero),
            .landscapeRight
        )
        XCTAssertEqual(
            NativeFullscreenOrientationLease.fullscreenTargetOrientation(
                presentationSize: CGSize(width: CGFloat.infinity, height: 1080)
            ),
            .landscapeRight
        )
    }

    func testMaskMapsInterfaceOrientation() {
        XCTAssertEqual(NativeFullscreenOrientationLease.mask(for: .portrait), .portrait)
        XCTAssertEqual(NativeFullscreenOrientationLease.mask(for: .landscapeRight), .landscapeRight)
        XCTAssertEqual(NativeFullscreenOrientationLease.mask(for: .landscapeLeft), .landscapeLeft)
        XCTAssertNil(NativeFullscreenOrientationLease.mask(for: .unknown))
    }

    func testExitOrientationRestoresPortraitEntry() {
        XCTAssertEqual(
            NativeFullscreenOrientationLease.exitOrientation(
                entry: .portrait,
                fullscreen: .landscapeRight
            ),
            .portrait
        )
    }

    func testExitOrientationKeepsLandscapeContextWhenEnteredFromLandscape() {
        XCTAssertEqual(
            NativeFullscreenOrientationLease.exitOrientation(
                entry: .landscapeLeft,
                fullscreen: .landscapeRight
            ),
            .landscapeRight
        )
        XCTAssertEqual(
            NativeFullscreenOrientationLease.exitOrientation(
                entry: .landscapeRight,
                fullscreen: nil
            ),
            .landscapeRight
        )
    }

    func testBeginEntryAppliesTargetMaskAndBeginRestoreComputesExitTarget() {
        let lease = NativeFullscreenOrientationLease()
        lease.beginEntry(target: .landscapeRight, entry: .portrait, scene: nil)
        XCTAssertEqual(lease.phase, .entering(target: .landscapeRight))

        lease.beginFullscreenRotation()
        XCTAssertEqual(lease.phase, .fullscreen)

        lease.beginRestore()
        XCTAssertEqual(lease.phase, .restoring(target: .portrait))

        lease.cancel()
        XCTAssertNil(lease.phase)
    }

    func testCancelWithoutReleaseDoesNotInvokeOnRelease() {
        let lease = NativeFullscreenOrientationLease()
        var releaseCount = 0
        lease.onRelease = { releaseCount += 1 }
        lease.beginEntry(target: .portrait, entry: .portrait, scene: nil)
        lease.cancel()
        XCTAssertEqual(releaseCount, 0)
    }

    func testCustomClearGlassControlsInheritHostAppearanceUnderLightThemeHost() async throws {
        let landscapeURL = try await makeLocalLandscapeVideo()
        defer { try? FileManager.default.removeItem(at: landscapeURL) }

        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.overrideUserInterfaceStyle = .light
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }

        let dependencies = AppDependencies()
        let navModel = NativeControlsRegressionNavModel()
        let hosting = UIHostingController(
            rootView: NativeControlsRegressionHost(dependencies: dependencies, navModel: navModel)
        )
        window.rootViewController = hosting
        window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(400))

        AppOrientationLock.restorePortrait()

        let video = try JSONDecoder.bili.decode(
            VideoItem.self,
            from: Data(
                #"{"bvid":"BVCustomGlassReg","title":"CustomGlassReg","cid":1,"dimension":{"width":1920,"height":1080}}"#.utf8
            )
        )
        navModel.path.append(video)
        try await Task.sleep(for: .milliseconds(800))

        let bridge = try XCTUnwrap(findBridgeController(from: hosting))
        let containerVC = try XCTUnwrap(
            bridge.children.compactMap { $0 as? VideoDetailSwiftUIContainerViewController }.first
        )

        let engine = AVPlayerHLSBridgeEngine()
        let playerVM = PlayerStateViewModel(
            videoURL: landscapeURL,
            audioURL: nil,
            title: "CustomGlassReg",
            referer: "https://www.bilibili.com",
            engine: engine
        )
        try await engine.prepare(
            source: PlayerStreamSource(
                metricsID: UUID().uuidString,
                videoURL: landscapeURL,
                audioURL: nil,
                videoStream: nil,
                audioStream: nil,
                alternateVideoRenditions: [],
                referer: "https://www.bilibili.com",
                httpHeaders: [:],
                title: "CustomGlassReg",
                durationHint: 10,
                isLiveStream: false,
                isLiveHLS: false,
                liveHLSFormat: nil,
                resumeTime: 0,
                dynamicRange: .sdr,
                cdnPreference: .automatic
            )
        )

        let variant1080 = PlayVariant(
            quality: 80,
            title: "1080P 高清",
            videoURL: URL(string: "https://example.com/1080.mp4"),
            audioURL: nil,
            videoStream: nil,
            audioStream: nil,
            codec: "hev1",
            resolution: "1920x1080",
            frameRate: "30",
            bandwidth: 2_000_000,
            isHDR: false,
            badge: nil
        )
        let variant720 = PlayVariant(
            quality: 64,
            title: "720P 高清",
            videoURL: URL(string: "https://example.com/720.mp4"),
            audioURL: nil,
            videoStream: nil,
            audioStream: nil,
            codec: "avc1",
            resolution: "1280x720",
            frameRate: "30",
            bandwidth: 1_000_000,
            isHDR: false,
            badge: nil
        )
        var snapshot = VideoDetailQualityControlRenderSnapshot()
        snapshot.qualityInlineButtonTitle = "1080P"
        snapshot.qualityAccessoryButtonTitle = "1080P"
        snapshot.qualityMenuItems = [
            VideoDetailPlaybackQualityMenuItem(
                variant: variant1080,
                title: "1080P 高清",
                subtitle: nil,
                systemImage: "checkmark",
                isDisabled: false
            ),
            VideoDetailPlaybackQualityMenuItem(
                variant: variant720,
                title: "720P 高清",
                subtitle: nil,
                systemImage: "circle",
                isDisabled: false
            ),
        ]
        containerVC.viewModel.stablePlayerViewModel = playerVM
        defer {
            bridge.prepareForDismantle()
            containerVC.viewModel.stopPlaybackForNavigation()
        }
        try await Task.sleep(for: .milliseconds(400))
        engine.play()
        await waitForPlayURLSettlement(on: containerVC.viewModel)
        containerVC.viewModel.playbackRenderStore.qualityControlStore.update(snapshot)
        try await Task.sleep(for: .milliseconds(150))
        window.layoutIfNeeded()
        XCTAssertTrue(containerVC.viewModel.playbackRenderStore.qualityControlStore.hasQualityMenu)

        XCTAssertEqual(bridge.traitCollection.userInterfaceStyle, .light)
        XCTAssertNil(findView(accessibilityIdentifier: "ui.player.nativeControlsGroup", in: bridge.view))
        if let playerVC = findAVPlayerViewController(in: bridge.view) {
            XCTAssertFalse(playerVC.showsPlaybackControls)
        }

        let directSurface = try XCTUnwrap(
            findView(matchingClassSubstring: "DirectUIKitPlayerSurfaceHostView", in: bridge.view)
        )
        let surfaceHost = try XCTUnwrap(directSurface.superview as? VideoDetailShellSurfaceHost)
        XCTAssertFalse(directSurface.isUserInteractionEnabled)
        surfaceHost.revealPlaybackControlsForTesting()
        try await Task.sleep(for: .milliseconds(250))
        window.layoutIfNeeded()

        let overlayView = try XCTUnwrap(
            surfaceHost.subviews.first { NSStringFromClass(type(of: $0)).contains("_UIHostingView") }
        )
        var overlayHostingCandidate: UIViewController?
        var responder: UIResponder? = overlayView.next
        while let current = responder {
            if let vc = current as? UIViewController {
                overlayHostingCandidate = vc
                break
            }
            responder = current.next
        }
        let overlayHosting = try XCTUnwrap(overlayHostingCandidate)
        XCTAssertTrue(NSStringFromClass(type(of: overlayHosting)).contains("UIHostingController"))
        XCTAssertEqual(overlayHosting.overrideUserInterfaceStyle, .unspecified)
        XCTAssertEqual(overlayHosting.traitCollection.userInterfaceStyle, .dark)
        XCTAssertEqual(overlayHosting.view.traitCollection.userInterfaceStyle, .dark)
        XCTAssertTrue(overlayHosting.view.isUserInteractionEnabled)

        let qualityQuickButton = try XCTUnwrap(
            findView(accessibilityIdentifier: "ui.player.quality.quick", in: overlayHosting.view)
        )
        XCTAssertGreaterThan(qualityQuickButton.bounds.width, 10)
        XCTAssertGreaterThan(qualityQuickButton.bounds.height, 10)
        XCTAssertEqual(qualityQuickButton.overrideUserInterfaceStyle, .dark)
        XCTAssertEqual(qualityQuickButton.traitCollection.userInterfaceStyle, .dark)
        let qualityFrameInOverlay = qualityQuickButton.convert(qualityQuickButton.bounds, to: overlayHosting.view)
        XCTAssertGreaterThan(qualityFrameInOverlay.midY, overlayHosting.view.bounds.midY)

        let qualityCenterInBridge = qualityQuickButton.convert(
            CGPoint(x: qualityQuickButton.bounds.midX, y: qualityQuickButton.bounds.midY),
            to: bridge.view
        )
        let qualityHitView = bridge.view.hitTest(qualityCenterInBridge, with: nil)
        XCTAssertNotNil(qualityHitView)
        if let qualityHitView {
            XCTAssertTrue(qualityHitView.isDescendant(of: overlayHosting.view))
        }

        let overlayCenterInBridge = overlayHosting.view.convert(
            CGPoint(x: overlayHosting.view.bounds.midX, y: overlayHosting.view.bounds.midY),
            to: bridge.view
        )
        let centerHitView = bridge.view.hitTest(overlayCenterInBridge, with: nil)
        XCTAssertNotNil(centerHitView)
        if let centerHitView {
            XCTAssertTrue(centerHitView.isDescendant(of: overlayHosting.view))
        }

        window.rootViewController = nil
        try await Task.sleep(for: .milliseconds(200))
    }

    func testNativeSurfaceWithCustomControlsModeMountsAVPlayerViewControllerAndInteractiveCustomGlassOverlay() async throws {
        // Verify live VideoDetailShellSurfaceHost in `.customOverlay` ("原生底座 + 自绘控件") mode:
        let landscapeURL = try await makeLocalLandscapeVideo()
        defer { try? FileManager.default.removeItem(at: landscapeURL) }

        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.overrideUserInterfaceStyle = .light
        defer {
            AppOrientationLock.restorePortrait(in: scene)
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }

        let dependencies = AppDependencies()

        let navModel = NativeControlsRegressionNavModel()
        let hosting = UIHostingController(
            rootView: NativeControlsRegressionHost(dependencies: dependencies, navModel: navModel)
        )
        window.rootViewController = hosting
        window.makeKeyAndVisible()
        AppOrientationLock.restorePortrait(in: scene)
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
        try await Task.sleep(for: .milliseconds(500))

        let video = try JSONDecoder.bili.decode(
            VideoItem.self,
            from: Data(
                #"{"bvid":"BVNativeBaseCustomChrome","title":"NativeBaseCustomChrome","cid":1,"dimension":{"width":1920,"height":1080}}"#.utf8
            )
        )
        navModel.path.append(video)
        try await Task.sleep(for: .milliseconds(700))

        let bridge = try XCTUnwrap(findBridgeController(from: hosting))
        let containerVC = try XCTUnwrap(
            bridge.children.compactMap { $0 as? VideoDetailSwiftUIContainerViewController }.first
        )
        await waitForPlayURLSettlement(on: containerVC.viewModel)

        let engine = AVPlayerHLSBridgeEngine()
        let playerVM = PlayerStateViewModel(
            videoURL: landscapeURL,
            audioURL: nil,
            title: "NativeBaseCustomChrome",
            referer: "https://www.bilibili.com",
            engine: engine
        )
        try await engine.prepare(
            source: PlayerStreamSource(
                metricsID: UUID().uuidString,
                videoURL: landscapeURL,
                audioURL: nil,
                videoStream: nil,
                audioStream: nil,
                alternateVideoRenditions: [],
                referer: "https://www.bilibili.com",
                httpHeaders: [:],
                title: "NativeBaseCustomChrome",
                durationHint: 10,
                isLiveStream: false,
                isLiveHLS: false,
                liveHLSFormat: nil,
                resumeTime: 0,
                dynamicRange: .sdr,
                cdnPreference: .automatic
            )
        )
        let variant1080 = PlayVariant(
            quality: 80,
            title: "1080P 高清",
            videoURL: landscapeURL,
            audioURL: nil,
            videoStream: nil,
            audioStream: nil,
            codec: "avc1",
            resolution: "1920x1080",
            frameRate: "30",
            bandwidth: 2_000_000,
            isHDR: false,
            badge: nil
        )
        var snapshot = VideoDetailQualityControlRenderSnapshot()
        snapshot.qualityInlineButtonTitle = "1080P"
        snapshot.qualityAccessoryButtonTitle = "1080P"
        snapshot.qualityMenuItems = [
            VideoDetailPlaybackQualityMenuItem(
                variant: variant1080,
                title: "1080P 高清",
                subtitle: nil,
                systemImage: "checkmark",
                isDisabled: false
            )
        ]
        containerVC.viewModel.stablePlayerViewModel = playerVM
        try await Task.sleep(for: .milliseconds(400))
        engine.play()
        await waitForPlayURLSettlement(on: containerVC.viewModel)
        containerVC.viewModel.playbackRenderStore.qualityControlStore.update(snapshot)
        try await Task.sleep(for: .milliseconds(500))
        window.layoutIfNeeded()

        // Official AVPlayerViewController IS mounted as the video surface, with system controls OFF:
        let playerVC = try XCTUnwrap(findAVPlayerViewController(in: bridge.view))
        XCTAssertNotNil(playerVC.parent, "AVPlayerViewController must be mounted as native video base")
        XCTAssertFalse(playerVC.showsPlaybackControls, "System AVKit controls (AirPlay/Audio/Subtitles) must be hidden")
        XCTAssertFalse(playerVC.allowsVideoFrameAnalysis, "Live Text OCR must be off while custom overlay owns hit-testing")
        let contentOverlayGestures = playerVC.contentOverlayView?.subviews.flatMap { $0.gestureRecognizers ?? [] } ?? []
        XCTAssertTrue(
            contentOverlayGestures.isEmpty,
            "NativePlayerSurfaceGestureController must detach so BiliPlayerSurfaceGestureLayerHost is sole gesture owner"
        )
        XCTAssertNil(
            findView(accessibilityIdentifier: "ui.player.nativeControlsGroup", in: bridge.view),
            "System-controls accessory group should not be installed in customOverlay mode"
        )

        // Custom dark Liquid Glass controls ARE mounted and interactive over the native surface:
        let surfaceHost = try XCTUnwrap(
            findView(matchingClassSubstring: "VideoDetailShellSurfaceHost", in: bridge.view) as? VideoDetailShellSurfaceHost
        )
        surfaceHost.revealPlaybackControlsForTesting()
        try await Task.sleep(for: .milliseconds(250))
        window.layoutIfNeeded()

        let customQualityPill = try XCTUnwrap(
            findView(accessibilityIdentifier: "ui.player.quality.quick", in: surfaceHost),
            "Custom dark Liquid Glass quality control must be mounted over AVPlayerViewController"
        )
        XCTAssertEqual(customQualityPill.traitCollection.userInterfaceStyle, .dark)

        let centerPoint = surfaceHost.convert(
            CGPoint(x: surfaceHost.bounds.midX, y: surfaceHost.bounds.midY),
            to: bridge.view
        )
        let centerHit = try XCTUnwrap(bridge.view.hitTest(centerPoint, with: nil))
        XCTAssertFalse(
            centerHit.isDescendant(of: playerVC.view),
            "Touches in customOverlay mode must route to custom gesture/controls overlay rather than AVPlayerViewController"
        )

        // Custom fullscreen rotation works cleanly in `.customOverlay` mode while keeping AVPlayerViewController inline:
        containerVC.rotationDelegate?.requestVideoDetailFullscreen()
        try await Task.sleep(for: .milliseconds(800))
        window.layoutIfNeeded()
        XCTAssertGreaterThan(bridge.view.bounds.width, bridge.view.bounds.height)
        XCTAssertNil(playerVC.presentingViewController)
        XCTAssertFalse(playerVC.showsPlaybackControls)

        containerVC.rotationDelegate?.requestVideoDetailExitFullscreen()
        try await Task.sleep(for: .milliseconds(800))
        window.layoutIfNeeded()
        XCTAssertGreaterThan(bridge.view.bounds.height, bridge.view.bounds.width)

        bridge.prepareForDismantle()
        containerVC.viewModel.stopPlaybackForNavigation()
        window.rootViewController = nil
        try await Task.sleep(for: .milliseconds(200))
    }

    private func waitForPlayURLSettlement(on viewModel: VideoDetailViewModel) async {
        let deadline = ContinuousClock.now + .seconds(4)
        while ContinuousClock.now < deadline {
            if case .failed = viewModel.playbackRenderStore.playURLState {
                try? await Task.sleep(for: .milliseconds(50))
                return
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func enclosingVisualEffectView(of view: UIView) -> UIVisualEffectView? {
        var current = view.superview
        while let candidate = current {
            if let ev = candidate as? UIVisualEffectView { return ev }
            current = candidate.superview
        }
        return nil
    }

    private func findView(matchingClassSubstring substr: String, in root: UIView) -> UIView? {
        if NSStringFromClass(type(of: root)).contains(substr) { return root }
        return root.subviews.lazy.compactMap { self.findView(matchingClassSubstring: substr, in: $0) }.first
    }

    private func findView(accessibilityIdentifier id: String, in root: UIView) -> UIView? {
        if root.accessibilityIdentifier == id { return root }
        return root.subviews.lazy.compactMap { self.findView(accessibilityIdentifier: id, in: $0) }.first
    }

    private func findView(accessibilityLabel label: String, in root: UIView) -> UIView? {
        if root.accessibilityLabel == label { return root }
        return root.subviews.lazy.compactMap { self.findView(accessibilityLabel: label, in: $0) }.first
    }

    private func findBridgeController(from vc: UIViewController) -> VideoDetailRotationBridgeViewController? {
        if let bridge = vc as? VideoDetailRotationBridgeViewController { return bridge }
        return vc.children.lazy.compactMap { self.findBridgeController(from: $0) }.first
    }

    private func findAVPlayerViewController(in view: UIView) -> AVPlayerViewController? {
        for subview in view.subviews {
            if let controller = subview.next as? AVPlayerViewController { return controller }
            if let found = findAVPlayerViewController(in: subview) { return found }
        }
        return nil
    }

    private func makeLocalLandscapeVideo() async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 320,
                AVVideoHeightKey: 180,
            ]
        )
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: 320,
                kCVPixelBufferHeightKey as String: 180,
            ]
        )
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for index in 0...10 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            if let buffer {
                adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 1))
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        return url
    }
}

@MainActor
private final class NativeControlsRegressionNavModel: ObservableObject {
    @Published var path = NavigationPath()
}

private struct NativeControlsRegressionHost: View {
    let dependencies: AppDependencies
    @ObservedObject var navModel: NativeControlsRegressionNavModel

    var body: some View {
        TabView {
            Tab("首页", systemImage: "house") {
                NavigationStack(path: $navModel.path) {
                    Color.white
                        .videoDestinations(usesTransparentNavigationBar: true)
                }
            }
        }
        .environmentObject(dependencies)
        .environmentObject(dependencies.sessionStore)
        .environmentObject(dependencies.libraryStore)
        .environmentObject(dependencies.homeRecommendDiagnosticsStore)
        .environment(\.colorScheme, .light)
        .environment(\.appContentColorScheme, .light)
        .preferredColorScheme(.dark)
    }
}
