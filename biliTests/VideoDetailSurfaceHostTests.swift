import AVFoundation
import QuartzCore
import UIKit
import XCTest
@testable import bili

@MainActor
final class VideoDetailSurfaceHostTests: XCTestCase {
    // A deterministic local-media probe. This measures layout work, not the
    // duration of a system rotation animation or visible black-frame duration.
    func testCompareSurfaceHostsAcrossTwentyGeometryCycles() async throws {
        let mediaURL = try await makeLocalVideo()
        defer { try? FileManager.default.removeItem(at: mediaURL) }
        for direct in [false, true] {
            let engine = AVPlayerHLSBridgeEngine()
            let player = PlayerStateViewModel(videoURL: mediaURL, audioURL: nil, title: "Surface probe", referer: "https://www.bilibili.com", engine: engine)
            try await engine.prepare(source: PlayerStreamSource(metricsID: UUID().uuidString, videoURL: mediaURL, audioURL: nil, videoStream: nil, audioStream: nil, alternateVideoRenditions: [], referer: "https://www.bilibili.com", httpHeaders: [:], title: "Surface probe", durationHint: 20, isLiveStream: false, isLiveHLS: false, liveHLSFormat: nil, resumeTime: 0, dynamicRange: .sdr, cdnPreference: .automatic))
            var attaches = 0
            var detaches = 0
            player.onVideoDetailPlaybackDiagnosticSurfaceEvent = { event in
                switch event {
                case .attached: attaches += 1
                case .detached: detaches += 1
                }
            }
            let host = VideoDetailPlayerSurfaceHostFactory.make(viewModel: player,
                isPictureInPictureEnabled: false, usesDirectUIKitSurface: direct)
            let parent = UIViewController()
            parent.loadViewIfNeeded()
            let previousWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows).first { $0.isKeyWindow }
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            window.rootViewController = parent
            window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil; previousWindow?.makeKey() }
            parent.view.addSubview(host.hostedView)
            host.attach(to: parent)
            host.hostedView.frame = CGRect(x: 0, y: 0, width: 402, height: 226)
            host.refreshLayoutImmediately()
            try await Task.sleep(for: .milliseconds(100))
            let surface = try XCTUnwrap(findSurface(in: host.hostedView))
            let surfaceID = ObjectIdentifier(surface)
            let playerID = try XCTUnwrap(player.debugAVPlayerIdentity)
            let itemID = try XCTUnwrap(player.debugAVPlayerItemIdentity)
            let initialAttaches = attaches
            let initialDetaches = detaches
            var immediateCorrect = 0
            var passiveImmediateCorrect = 0
            var elapsed = 0.0
            for cycle in 0..<20 {
                if cycle == 0 { engine.play() }
                if cycle == 7 { _ = engine.seek(toTime: 5) }
                if cycle == 10 { engine.pause() }
                for size in [CGSize(width: 874, height: 402), CGSize(width: 402, height: 226)] {
                    let start = CACurrentMediaTime()
                    host.hostedView.frame.size = size
                    host.hostedView.layoutIfNeeded()
                    if layerMatchesSurface(surface, size: size) { passiveImmediateCorrect += 1 }
                    host.refreshLayoutImmediately()
                    elapsed += (CACurrentMediaTime() - start) * 1_000
                    if layerMatchesSurface(surface, size: size) { immediateCorrect += 1 }
                    // The compatibility host updates asynchronously. Do not
                    // mistake a busy simulator taking >20ms for a failed layout.
                    let layoutDeadline = ContinuousClock.now + .milliseconds(500)
                    while !layerMatchesSurface(surface, size: size), ContinuousClock.now < layoutDeadline {
                        try await Task.sleep(for: .milliseconds(5))
                    }
                    XCTAssertTrue(layerMatchesSurface(surface, size: size), "direct=\(direct) expected=\(size) surface=\(surface.bounds) drawable=\(surface.drawableView.bounds) layers=\(surface.drawableView.layer.sublayers ?? [])")
                    XCTAssertEqual(ObjectIdentifier(try XCTUnwrap(findSurface(in: host.hostedView))), surfaceID)
                    XCTAssertEqual(player.debugAVPlayerIdentity, playerID)
                    XCTAssertEqual(player.debugAVPlayerItemIdentity, itemID)
                    try await Task.sleep(for: .milliseconds(20))
                }
            }
            if direct { XCTAssertEqual(passiveImmediateCorrect, 40) }
            XCTAssertEqual(attaches, initialAttaches)
            XCTAssertEqual(detaches, initialDetaches)
            XCTAssertEqual(parent.children.count, direct ? 0 : 1)
            let result = "SurfaceHostProbe direct=\(direct) geometryUpdates=40 immediateCorrect=\(immediateCorrect) passiveImmediateCorrect=\(passiveImmediateCorrect) synchronousLayoutTotalMs=\(elapsed) children=\(parent.children.count) rotationAttach=\(attaches - initialAttaches) rotationDetach=\(detaches - initialDetaches) itemStable=true decodedFrames=unavailable"
            print(result)
            let attachment = XCTAttachment(string: result)
            attachment.name = "Surface probe direct=\(direct)"
            attachment.lifetime = .keepAlways
            add(attachment)
            host.tearDown()
            host.tearDown()
            XCTAssertNil(findSurface(in: host.hostedView))
            XCTAssertTrue(parent.children.isEmpty)
            player.stop()
        }
    }

    func testExperimentDefaultsOffAndPersistsWithoutChangingOtherSettings() {
        let name = "SurfaceExperimentTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = LibraryStore(userDefaults: defaults)
        let pip = store.pictureInPictureEnabled
        XCTAssertFalse(store.videoDetailUIKitSurfaceRotationExperimentEnabled)
        store.setVideoDetailUIKitSurfaceRotationExperimentEnabled(true)
        XCTAssertTrue(LibraryStore(userDefaults: defaults).videoDetailUIKitSurfaceRotationExperimentEnabled)
        store.setVideoDetailUIKitSurfaceRotationExperimentEnabled(false)
        XCTAssertFalse(LibraryStore(userDefaults: defaults).videoDetailUIKitSurfaceRotationExperimentEnabled)
        XCTAssertEqual(store.pictureInPictureEnabled, pip)
    }

    func testFactoryKeepsLegacyHostWhenDisabled() {
        let player = makePlayer()
        let legacy = VideoDetailPlayerSurfaceHostFactory.make(viewModel: player,
            isPictureInPictureEnabled: false, usesDirectUIKitSurface: false)
        XCTAssertTrue(legacy is VideoDetailSwiftUISurfaceHostingView)
        legacy.tearDown()
        let direct = VideoDetailPlayerSurfaceHostFactory.make(viewModel: player,
            isPictureInPictureEnabled: false, usesDirectUIKitSurface: true)
        XCTAssertTrue(direct is DirectUIKitPlayerSurfaceHostView)
        direct.tearDown()
        player.stop()
    }

    func testDirectSurfaceRebindAndIdempotentTeardown() throws {
        let first = makePlayer()
        let second = makePlayer()
        let host = DirectUIKitPlayerSurfaceHostView(viewModel: first, isPictureInPictureEnabled: false)
        let original = try XCTUnwrap(findSurface(in: host))
        host.setPlayerViewModel(first)
        XCTAssertTrue(original.isBound(to: first))
        host.setPlayerViewModel(second)
        XCTAssertTrue(original.isBound(to: second))
        XCTAssertTrue(findSurface(in: host) === original)
        host.tearDown()
        host.tearDown()
        host.setPlayerViewModel(first)
        XCTAssertNil(findSurface(in: host))
        first.stop()
        second.stop()
    }

    func testSynchronousBoundsRefreshCancelsPendingDeferredRefresh() async throws {
        let player = makePlayer()
        let host = DirectUIKitPlayerSurfaceHostView(
            viewModel: player,
            isPictureInPictureEnabled: false,
            synchronizesBoundsRefresh: true
        )
        defer {
            host.tearDown()
            player.stop()
        }

        host.frame = CGRect(x: 0, y: 0, width: 402, height: 226)
        host.setNeedsLayout()
        host.layoutIfNeeded()
        let surface = try XCTUnwrap(findSurface(in: host))
        let refreshCountAfterSynchronousLayout = surface.debugBoundSurfaceLayoutRefreshCount
        XCTAssertGreaterThan(refreshCountAfterSynchronousLayout, 0)

        try await Task.sleep(for: .milliseconds(25))
        XCTAssertEqual(
            surface.debugBoundSurfaceLayoutRefreshCount,
            refreshCountAfterSynchronousLayout,
            "A synchronous bounds refresh should satisfy and cancel the pending deferred refresh."
        )
    }

    func testShellKeepsOverlayIdentityAndReleasesBothHostModes() async throws {
        let dependencies = AppDependencies()
        let store = dependencies.libraryStore
        let previous = store.videoDetailUIKitSurfaceRotationExperimentEnabled
        defer { store.setVideoDetailUIKitSurfaceRotationExperimentEnabled(previous) }
        let video = try JSONDecoder.bili.decode(VideoItem.self,
            from: Data(#"{"bvid":"BVSurfaceProbe","title":"Surface probe","cid":1}"#.utf8))
        let detail = VideoDetailViewModel(seedVideo: video, api: dependencies.api,
            libraryStore: store, sessionStore: dependencies.sessionStore,
            sponsorBlockService: dependencies.sponsorBlockService)
        let runtime = VideoDetailRuntimeSettingsStore()
        runtime.bind(store)
        for direct in [false, true] {
            store.setVideoDetailUIKitSurfaceRotationExperimentEnabled(direct)
            let player = makePlayer()
            let parent = UIViewController()
            parent.loadViewIfNeeded()
            weak var releasedHost: VideoDetailShellSurfaceHost?
            do {
                let host = VideoDetailShellSurfaceHost(playerViewModel: player,
                    detailViewModel: detail, dependencies: dependencies, runtimeSettings: runtime,
                    rotationCoordinator: PlaybackRotationCoordinator(), onShowMoreControls: { _ in },
                    onDismissMoreControls: {}, onRequestFullscreen: {}, onExitFullscreen: {},
                    onToggleDanmaku: {}, onShowDanmakuSettings: {}, onNavigateBack: {})
                releasedHost = host
                parent.view.addSubview(host)
                host.attach(to: parent)
                XCTAssertEqual(parent.children.count, direct ? 1 : 2)
                let overlay = try XCTUnwrap(parent.children.last)
                for size in [CGSize(width: 402, height: 226), CGSize(width: 874, height: 402), CGSize(width: 402, height: 54)] {
                    host.frame.size = size
                    host.refreshLayoutImmediately()
                    XCTAssertTrue(parent.children.last === overlay)
                    XCTAssertEqual(overlay.view.frame, host.bounds)
                }
                // A settings change must not migrate the in-flight surface or overlay.
                store.setVideoDetailUIKitSurfaceRotationExperimentEnabled(!direct)
                XCTAssertEqual(parent.children.count, direct ? 1 : 2)
                host.tearDown()
                host.tearDown()
                host.removeFromSuperview()
                XCTAssertTrue(parent.children.isEmpty)
            }
            await Task.yield()
            XCTAssertNil(releasedHost)
            player.stop()
        }
    }

    private func makeLocalVideo() async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 180,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for index in 0...20 {
            let deadline = ContinuousClock.now + .seconds(5)
            while !input.isReadyForMoreMediaData {
                guard ContinuousClock.now < deadline else {
                    throw NSError(domain: "SurfaceProbeVideoWriter", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for video writer"])
                }
                try await Task.sleep(for: .milliseconds(5))
            }
            var buffer: CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferPoolCreatePixelBuffer(nil, try XCTUnwrap(adaptor.pixelBufferPool), &buffer), kCVReturnSuccess)
            let pixelBuffer = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            let bytes = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixelBuffer)).assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
            for y in 0..<180 {
                for x in 0..<320 {
                    let offset = y * stride + x * 4
                    bytes[offset] = 255
                    bytes[offset + 1] = x < 160 ? 240 : 20
                    bytes[offset + 2] = x < 160 ? 20 : 240
                    bytes[offset + 3] = 40
                }
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            XCTAssertTrue(adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: Int64(index), timescale: 1)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        return url
    }

    private func makePlayer() -> PlayerStateViewModel {
        PlayerStateViewModel(videoURL: nil, audioURL: nil, title: "Surface geometry probe",
            referer: "https://www.bilibili.com", engine: AVPlayerHLSBridgeEngine())
    }

    private func findSurface(in view: UIView) -> VideoSurfaceContainerView? {
        if let surface = view as? VideoSurfaceContainerView { return surface }
        return view.subviews.lazy.compactMap { self.findSurface(in: $0) }.first
    }

    private func layerMatchesSurface(_ surface: VideoSurfaceContainerView, size: CGSize) -> Bool {
        let layer = surface.drawableView.layer.sublayers?.compactMap { $0 as? AVPlayerLayer }.first
        return surface.bounds.size == size && surface.drawableView.bounds.size == size
            && layer?.frame.size == size && layer?.videoGravity == .resizeAspect
    }
}
