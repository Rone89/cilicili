import AVFoundation
import QuartzCore
import UIKit
import XCTest
@testable import bili

@MainActor
final class VideoDetailSurfaceHostTests: XCTestCase {
    // A deterministic local-media probe. This measures layout work, not the
    // duration of a system rotation animation or visible black-frame duration.
    func testProductionSurfaceAcrossTwentyGeometryCycles() async throws {
        let mediaURL = try await makeLocalVideo()
        defer { try? FileManager.default.removeItem(at: mediaURL) }
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
        let host = DirectUIKitPlayerSurfaceHostView(viewModel: player,
            isPictureInPictureEnabled: false)
        let parent = UIViewController()
        parent.loadViewIfNeeded()
        let previousWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first { $0.isKeyWindow }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = parent
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previousWindow?.makeKey() }
        parent.view.addSubview(host)
        host.frame = CGRect(x: 0, y: 0, width: 402, height: 226)
        host.refreshLayoutImmediately()
        try await Task.sleep(for: .milliseconds(100))
        let surface = try XCTUnwrap(findSurface(in: host))
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
                host.frame.size = size
                host.layoutIfNeeded()
                if layerMatchesSurface(surface, size: size) { passiveImmediateCorrect += 1 }
                host.refreshLayoutImmediately()
                elapsed += (CACurrentMediaTime() - start) * 1_000
                if layerMatchesSurface(surface, size: size) { immediateCorrect += 1 }
                // Bound the wait so any delayed layout regression is reported.
                let layoutDeadline = ContinuousClock.now + .milliseconds(500)
                while !layerMatchesSurface(surface, size: size), ContinuousClock.now < layoutDeadline {
                    try await Task.sleep(for: .milliseconds(5))
                }
                XCTAssertTrue(layerMatchesSurface(surface, size: size), "expected=\(size) surface=\(surface.bounds) drawable=\(surface.drawableView.bounds) layers=\(surface.drawableView.layer.sublayers ?? [])")
                XCTAssertEqual(ObjectIdentifier(try XCTUnwrap(findSurface(in: host))), surfaceID)
                XCTAssertEqual(player.debugAVPlayerIdentity, playerID)
                XCTAssertEqual(player.debugAVPlayerItemIdentity, itemID)
                try await Task.sleep(for: .milliseconds(20))
            }
        }
        XCTAssertEqual(passiveImmediateCorrect, 40)
        XCTAssertEqual(attaches, initialAttaches)
        XCTAssertEqual(detaches, initialDetaches)
        XCTAssertEqual(parent.children.count, 0)
        let result = "SurfaceHostProbe geometryUpdates=40 immediateCorrect=\(immediateCorrect) passiveImmediateCorrect=\(passiveImmediateCorrect) synchronousLayoutTotalMs=\(elapsed) children=\(parent.children.count) rotationAttach=\(attaches - initialAttaches) rotationDetach=\(detaches - initialDetaches) itemStable=true decodedFrames=unavailable"
        print(result)
        let attachment = XCTAttachment(string: result)
        attachment.name = "Production surface probe"
        attachment.lifetime = .keepAlways
        add(attachment)
        host.tearDown()
        host.tearDown()
        XCTAssertNil(findSurface(in: host))
        XCTAssertTrue(parent.children.isEmpty)
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
            isPictureInPictureEnabled: false
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

    func testShellKeepsOverlayIdentityAndReleasesProductionHost() async throws {
        let dependencies = AppDependencies()
        let store = dependencies.libraryStore
        let video = try JSONDecoder.bili.decode(VideoItem.self,
            from: Data(#"{"bvid":"BVSurfaceProbe","title":"Surface probe","cid":1}"#.utf8))
        let detail = VideoDetailViewModel(seedVideo: video, api: dependencies.api,
            libraryStore: store, sessionStore: dependencies.sessionStore,
            sponsorBlockService: dependencies.sponsorBlockService)
        let runtime = VideoDetailRuntimeSettingsStore()
        runtime.bind(store)
        let player = makePlayer()
        let parent = UIViewController()
        parent.loadViewIfNeeded()
        weak var releasedHost: VideoDetailShellSurfaceHost?
        do {
            let host = VideoDetailShellSurfaceHost(playerViewModel: player,
                detailViewModel: detail, dependencies: dependencies, runtimeSettings: runtime,
                rotationCoordinator: PlaybackRotationCoordinator(), onShowMoreControls: { _ in },
                onDismissMoreControls: {}, onRequestFullscreen: {}, onExitFullscreen: {},
                onToggleDanmaku: {}, onShowDanmakuSettings: {})
            releasedHost = host
            parent.view.addSubview(host)
            host.attach(to: parent)
            XCTAssertEqual(parent.children.count, 1)
            let overlay = try XCTUnwrap(parent.children.last)
            for size in [CGSize(width: 402, height: 226), CGSize(width: 874, height: 402), CGSize(width: 402, height: 54)] {
                host.frame.size = size
                host.refreshLayoutImmediately()
                XCTAssertTrue(parent.children.last === overlay)
                XCTAssertEqual(overlay.view.frame, host.bounds)
            }
            host.tearDown()
            host.tearDown()
            host.removeFromSuperview()
            XCTAssertTrue(parent.children.isEmpty)
        }
        await Task.yield()
        XCTAssertNil(releasedHost)
        player.stop()
    }

    func testQualityTransitionFrameCoversRebindAndTracksGeometry() async throws {
        let dependencies = AppDependencies()
        let store = dependencies.libraryStore
        let detail = try makeDetail(dependencies: dependencies)
        let runtime = VideoDetailRuntimeSettingsStore()
        runtime.bind(store)
        let first = makePlayer()
        let second = makePlayer()
        first.setPlaybackIntent(false)
        second.setPlaybackIntent(false)
        let host = makeShellHost(player: first, detail: detail, dependencies: dependencies, runtime: runtime)
        let parent = UIViewController()
        parent.loadViewIfNeeded()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = parent
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previousWindow?.makeKey() }
        parent.view.addSubview(host)
        host.attach(to: parent)
        defer {
            host.tearDown()
            host.removeFromSuperview()
            first.stop()
            second.stop()
        }
        host.frame.size = CGSize(width: 402, height: 226)
        host.refreshLayoutImmediately()
        let surfaceDeadline = ContinuousClock.now + .seconds(2)
        while findSurface(in: host)?.isBound(to: first) != true, ContinuousClock.now < surfaceDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let surface = try XCTUnwrap(findSurface(in: host))
        XCTAssertTrue(surface.isBound(to: first))
        let imageView = try XCTUnwrap(host.subviews.compactMap { $0 as? UIImageView }.first)
        XCTAssertTrue(imageView.isHidden)
        let snapshot = makeTransitionSnapshot(color: .red)
        detail.playerIdentityRenderStore.update(.init(
            playerViewModel: second,
            transitionSnapshot: snapshot,
            transitionPlayerOpacity: 1
        ))
        // A synchronous publication must cover the old drawable BEFORE rebind.
        XCTAssertFalse(imageView.isHidden)
        XCTAssertTrue(imageView.image === snapshot.image)
        XCTAssertTrue(surface.isBound(to: first))
        XCTAssertTrue(host.subviews[1] === imageView)
        XCTAssertFalse(imageView.isUserInteractionEnabled)
        XCTAssertTrue(imageView.accessibilityElementsHidden)
        host.setPlayerViewModel(second)
        for size in [CGSize(width: 874, height: 402), CGSize(width: 402, height: 54)] {
            host.frame.size = size
            host.refreshLayoutImmediately()
            XCTAssertEqual(imageView.frame, host.bounds)
            XCTAssertFalse(imageView.isHidden)
            XCTAssertTrue(imageView.image === snapshot.image)
        }
        host.setVideoGravity(.resizeAspectFill)
        XCTAssertEqual(imageView.contentMode, .scaleAspectFill)
        host.setVideoGravity(.resizeAspect)
        XCTAssertEqual(imageView.contentMode, .scaleAspectFit)
        let nextSnapshot = makeTransitionSnapshot(color: .blue)
        detail.playerIdentityRenderStore.update(.init(
            playerViewModel: second, transitionSnapshot: nextSnapshot, transitionPlayerOpacity: 1
        ))
        XCTAssertTrue(imageView.image === nextSnapshot.image)
        detail.playerIdentityRenderStore.update(.init(playerViewModel: second))
        XCTAssertTrue(imageView.isHidden)
        XCTAssertNil(imageView.image)
        // An unavailable image must never introduce an opaque black mask.
        detail.playerIdentityRenderStore.update(.init(
            playerViewModel: second, transitionPlayerOpacity: 1
        ))
        XCTAssertTrue(imageView.isHidden)
        host.tearDown()
        detail.playerIdentityRenderStore.update(.init(
            playerViewModel: second, transitionSnapshot: nextSnapshot, transitionPlayerOpacity: 1
        ))
        XCTAssertNil(imageView.image)
        XCTAssertNil(imageView.superview)
        detail.playerIdentityRenderStore.update(.init())
    }

    func testQualityTransitionReleaseIgnoresStaleFirstFrameDuringRapidReplacement() async throws {
        let dependencies = AppDependencies()
        let detail = try makeDetail(dependencies: dependencies)
        let runtime = VideoDetailRuntimeSettingsStore()
        runtime.bind(dependencies.libraryStore)
        let first = makePlayer()
        let second = makePlayer()
        let third = makePlayer()
        for player in [first, second, third] {
            player.setPlaybackIntent(false)
            detail.configureStablePlayerStartupCallbacks(player)
        }
        let host = makeShellHost(player: first, detail: detail, dependencies: dependencies, runtime: runtime)
        defer {
            host.tearDown()
            detail.clearPlaybackTransitionPlayer()
            first.stop()
            second.stop()
            third.stop()
        }
        let imageView = try XCTUnwrap(host.subviews.compactMap { $0 as? UIImageView }.first)
        // Inject the captured-frame stage without mutating the player's private
        // decoder readiness. This test covers release callbacks and cancellation.
        detail.playbackTransitionPlayerViewModel = first
        detail.playbackTransitionSnapshot = makeTransitionSnapshot(color: .red)
        detail.playbackTransitionOpacity = 1
        detail.stablePlayerViewModel = second
        detail.syncPlayerIdentityRenderStore()
        detail.releasePlaybackTransitionPlayer(after: VideoDetailViewModel.playbackTransitionMaximumRetainNanoseconds)
        host.setPlayerViewModel(second)
        first.onFirstFramePresented?()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(imageView.isHidden, "The outgoing player's callback must not release the new transition.")
        second.onFirstFramePresented?()
        // Replace again while that first-frame release is still pending.
        detail.clearPlaybackTransitionPlayer()
        detail.playbackTransitionPlayerViewModel = second
        let blueSnapshot = makeTransitionSnapshot(color: .blue)
        detail.playbackTransitionSnapshot = blueSnapshot
        detail.playbackTransitionOpacity = 1
        detail.stablePlayerViewModel = third
        detail.syncPlayerIdentityRenderStore()
        detail.releasePlaybackTransitionPlayer(after: VideoDetailViewModel.playbackTransitionMaximumRetainNanoseconds)
        host.setPlayerViewModel(third)
        second.onFirstFramePresented?()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(imageView.isHidden)
        XCTAssertTrue(imageView.image === blueSnapshot.image)
        third.onFirstFramePresented?()
        let releaseDeadline = ContinuousClock.now + .seconds(2)
        while detail.playbackTransitionPlayerViewModel != nil, ContinuousClock.now < releaseDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(detail.playbackTransitionPlayerViewModel)
        XCTAssertTrue(imageView.isHidden)
        XCTAssertNil(imageView.image)
        XCTAssertTrue(second.isTerminated)
        XCTAssertFalse(third.isTerminated)
    }

    func testPlayerLayerFrameResyncsAfterStaleCoordinatorWrite() async throws {
        let player = makePlayer()
        let surface = VideoSurfaceContainerView()
        surface.configureBoundsRefresh(for: player)
        surface.setPlayerViewModel(player, prefersNativePlaybackControls: false)
        player.attachSurface(surface, prefersNativePlaybackControls: false)
        defer {
            surface.detachPlayerSurface()
            player.stop()
        }
        surface.frame = CGRect(x: 0, y: 0, width: 402, height: 226)
        surface.setNeedsLayout()
        surface.layoutIfNeeded()
        let layer = try XCTUnwrap(surface.drawableView.layer.sublayers?.compactMap { $0 as? AVPlayerLayer }.first)
        XCTAssertEqual(layer.frame.size, CGSize(width: 402, height: 226))

        surface.frame.size = CGSize(width: 874, height: 402)
        surface.setNeedsLayout()
        surface.layoutIfNeeded()
        let resizeDeadline = ContinuousClock.now + .seconds(2)
        while layer.frame.size != surface.drawableView.bounds.size, ContinuousClock.now < resizeDeadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(layer.frame.size, CGSize(width: 874, height: 402))
        // Let any pending deferred refresh drain before injecting the stale frame.
        try await Task.sleep(for: .milliseconds(30))

        // Simulate a coordinator write that landed on the pre-rotation geometry:
        // bounds are already final, so no bounds-change callback will fire again.
        layer.frame = CGRect(x: 0, y: 0, width: 402, height: 226)
        surface.setNeedsLayout()
        surface.layoutIfNeeded()
        XCTAssertEqual(
            layer.frame,
            CGRect(origin: .zero, size: surface.drawableView.bounds.size),
            "Every surface layout pass must resync stale AVPlayerLayer frames without waiting for a coordinator callback."
        )
    }

    func testShellHostReconcilesSwappedFullscreenBoundsOnlyAfterTransition() async throws {
        let dependencies = AppDependencies()
        let detail = try makeDetail(dependencies: dependencies)
        let runtime = VideoDetailRuntimeSettingsStore()
        runtime.bind(dependencies.libraryStore)
        let player = makePlayer()
        let coordinator = PlaybackRotationCoordinator()
        let host = makeShellHost(player: player, detail: detail, dependencies: dependencies,
                                 runtime: runtime, rotationCoordinator: coordinator)
        let parent = UIViewController()
        parent.loadViewIfNeeded()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = parent
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previousWindow?.makeKey() }
        parent.view.addSubview(host)
        host.attach(to: parent)
        defer {
            host.tearDown()
            host.removeFromSuperview()
            player.stop()
        }
        let windowSize = window.bounds.size
        XCTAssertNotEqual(windowSize.width, windowSize.height, "Probe needs a non-square window.")
        let staleSize = CGSize(width: windowSize.height, height: windowSize.width)

        // SwiftUI proposal lagged behind the rotation: host keeps the swapped size.
        host.frame = CGRect(origin: .zero, size: staleSize)
        coordinator.beginSystemTransition(toLandscape: true)
        host.setNeedsLayout()
        host.layoutIfNeeded()
        XCTAssertEqual(host.bounds.size, staleSize, "Reconciliation must not interrupt an in-flight rotation transition.")

        _ = coordinator.finishSystemTransition(toLandscape: true, currentOrientation: .landscapeRight)
        let reconcileDeadline = ContinuousClock.now + .seconds(2)
        while host.bounds.size != windowSize, ContinuousClock.now < reconcileDeadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(host.frame, CGRect(origin: .zero, size: windowSize),
                       "After the transition ends the host must reconcile to the real window bounds.")

        // A stale proposal re-applied after the transition is corrected by the
        // next layout pass alone, without another transition event.
        host.frame.size = staleSize
        host.setNeedsLayout()
        host.layoutIfNeeded()
        XCTAssertEqual(host.bounds.size, windowSize)

        // Inline player sizes never satisfy the swapped-size criterion.
        let inlineSize = CGSize(width: windowSize.width, height: 226)
        host.frame.size = inlineSize
        host.setNeedsLayout()
        host.layoutIfNeeded()
        XCTAssertEqual(host.bounds.size, inlineSize, "Inline layout must not be rewritten by the fullscreen reconciliation.")

        host.frame.size = windowSize
        host.setNeedsLayout()
        host.layoutIfNeeded()
        XCTAssertEqual(host.bounds.size, windowSize)
    }

    func testPortraitFullscreenConstrainsControlsAndDanmakuToCenteredNineSixteenArea() async throws {
        let dependencies = AppDependencies()
        let detail = try makeDetail(dependencies: dependencies)
        let runtime = VideoDetailRuntimeSettingsStore()
        runtime.bind(dependencies.libraryStore)
        let previousMetalPref = dependencies.libraryStore.metalDanmakuRendererExperimentEnabled
        dependencies.libraryStore.setMetalDanmakuRendererExperimentEnabled(false)
        defer {
            dependencies.libraryStore.setMetalDanmakuRendererExperimentEnabled(previousMetalPref)
        }

        let player = makePlayer()
        let coordinator = PlaybackRotationCoordinator()
        coordinator.activate(isLandscape: false)
        let host = makeShellHost(
            player: player,
            detail: detail,
            dependencies: dependencies,
            runtime: runtime,
            rotationCoordinator: coordinator
        )
        let parent = UIViewController()
        parent.loadViewIfNeeded()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        let portraitSize = CGSize(width: 440, height: 956)
        window.frame = CGRect(origin: .zero, size: portraitSize)
        window.rootViewController = parent
        window.makeKeyAndVisible()
        window.frame = CGRect(origin: .zero, size: portraitSize)
        defer { window.isHidden = true; window.rootViewController = nil; previousWindow?.makeKey() }
        parent.view.frame = window.bounds
        parent.view.addSubview(host)
        host.attach(to: parent)
        defer {
            host.tearDown()
            host.removeFromSuperview()
            player.stop()
        }

        host.frame = window.bounds
        host.setVideoAspectRatio(9.0 / 16.0)
        coordinator.setPortraitFullscreen(true)
        host.setNeedsLayout()
        host.layoutIfNeeded()

        let nineSixteenHeight = portraitSize.width * 16.0 / 9.0
        let nineSixteenMinY = (portraitSize.height - nineSixteenHeight) / 2
        let nineSixteenMaxY = portraitSize.height - nineSixteenMinY

        let deadline = ContinuousClock.now + .seconds(3)
        var moreButtonFrameInWindow: CGRect?
        var danmakuContentFrameInWindow: CGRect?
        while ContinuousClock.now < deadline {
            host.setNeedsLayout()
            host.layoutIfNeeded()
            if let moreButton = findView(withIdentifier: "ui.player.more", in: host) {
                let converted = moreButton.convert(moreButton.bounds, to: window)
                if converted.height > 1, converted.maxY <= nineSixteenMaxY {
                    moreButtonFrameInWindow = converted
                }
            }
            if let danmakuHost = findDanmakuHost(in: host) {
                if let syncView = danmakuHost.subviews.first as? DanmakuSynchronizedLayerView,
                   let contentFrame = syncView.debugContentFrame,
                   contentFrame.height > 1 {
                    let converted = syncView.convert(contentFrame, to: window)
                    if converted.minY >= nineSixteenMinY, converted.maxY <= nineSixteenMaxY {
                        danmakuContentFrameInWindow = converted
                    }
                } else if let kitView = danmakuHost.subviews.first as? DanmakuKitOverlayView,
                          let innerCanvas = kitView.subviews.first,
                          innerCanvas.frame.height > 1 {
                    let converted = innerCanvas.convert(innerCanvas.bounds, to: window)
                    if converted.minY >= nineSixteenMinY, converted.maxY <= nineSixteenMaxY {
                        danmakuContentFrameInWindow = converted
                    }
                }
            }
            if moreButtonFrameInWindow != nil, danmakuContentFrameInWindow != nil {
                break
            }
            try await Task.sleep(for: .milliseconds(15))
        }

        let buttonFrame = try XCTUnwrap(
            moreButtonFrameInWindow,
            "Portrait fullscreen bottom controls must sit inside the centered 9:16 region instead of the bottom letterbox bar."
        )
        XCTAssertGreaterThanOrEqual(buttonFrame.minY, nineSixteenMinY)
        XCTAssertLessThanOrEqual(buttonFrame.maxY, nineSixteenMaxY)

        let danmakuFrame = try XCTUnwrap(
            danmakuContentFrameInWindow,
            "Portrait fullscreen danmaku canvas must stay inside the centered 9:16 region."
        )
        XCTAssertGreaterThanOrEqual(danmakuFrame.minY, nineSixteenMinY + 7.5)
        XCTAssertLessThanOrEqual(danmakuFrame.maxY, nineSixteenMaxY - 83.5)
    }

    func testShellHostReconcilesShiftedAndInlineResidueBoundsInLandscapeFullscreen() async throws {
        let dependencies = AppDependencies()
        let detail = try makeDetail(dependencies: dependencies)
        let runtime = VideoDetailRuntimeSettingsStore()
        runtime.bind(dependencies.libraryStore)
        let player = makePlayer()
        let coordinator = PlaybackRotationCoordinator()
        let host = makeShellHost(
            player: player,
            detail: detail,
            dependencies: dependencies,
            runtime: runtime,
            rotationCoordinator: coordinator
        )
        let parent = UIViewController()
        parent.loadViewIfNeeded()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        let landscapeSize = CGSize(width: 874, height: 402)
        window.frame = CGRect(origin: .zero, size: landscapeSize)
        window.rootViewController = parent
        window.makeKeyAndVisible()
        window.frame = CGRect(origin: .zero, size: landscapeSize)
        XCTAssertEqual(window.bounds.size, landscapeSize)
        defer { window.isHidden = true; window.rootViewController = nil; previousWindow?.makeKey() }
        parent.view.frame = window.bounds
        parent.view.addSubview(host)
        host.attach(to: parent)
        defer {
            host.tearDown()
            host.removeFromSuperview()
            player.stop()
        }

        coordinator.beginSystemTransition(toLandscape: true)
        _ = coordinator.finishSystemTransition(toLandscape: true, currentOrientation: .landscapeRight)

        // 1) Inline portrait residue caused by pre-rotation chrome/safe-area update.
        host.frame = CGRect(x: 0, y: 59, width: 402, height: 226)
        host.setNeedsLayout()
        host.layoutIfNeeded()
        XCTAssertEqual(host.frame, CGRect(origin: .zero, size: landscapeSize))

        // 2) Safe-area cropped or origin-drifted frame after rotation completes.
        host.frame = CGRect(x: 0, y: 44, width: 874, height: 358)
        host.setNeedsLayout()
        host.layoutIfNeeded()
        XCTAssertEqual(host.frame, CGRect(origin: .zero, size: landscapeSize))

        // 3) Stale CoreAnimation animation left on host layer.
        let staleAnim = CABasicAnimation(keyPath: "position")
        staleAnim.duration = 0.35
        host.layer.add(staleAnim, forKey: "position")
        host.frame = CGRect(x: -100, y: 200, width: 402, height: 874)
        host.setNeedsLayout()
        host.layoutIfNeeded()
        XCTAssertEqual(host.frame, CGRect(origin: .zero, size: landscapeSize))
        XCTAssertTrue(host.layer.animationKeys()?.isEmpty ?? true)
    }

    func testSurfaceContainerStripsLayerAnimationsWhenResyncingPlayerLayerFrame() async throws {
        let player = makePlayer()
        let surface = VideoSurfaceContainerView()
        surface.disablesImplicitLayoutAnimations = true
        surface.configureBoundsRefresh(for: player, synchronously: true)
        surface.setPlayerViewModel(player, prefersNativePlaybackControls: false)
        player.attachSurface(surface, prefersNativePlaybackControls: false)
        defer {
            surface.detachPlayerSurface()
            player.stop()
        }

        let targetSize = CGSize(width: 874, height: 402)
        surface.frame = CGRect(origin: .zero, size: targetSize)
        surface.setNeedsLayout()
        surface.layoutIfNeeded()

        let layer = try XCTUnwrap(surface.drawableView.layer.sublayers?.compactMap { $0 as? AVPlayerLayer }.first)
        let staleAnimation = CABasicAnimation(keyPath: "position")
        staleAnimation.duration = 0.5
        layer.add(staleAnimation, forKey: "position")
        layer.frame = CGRect(x: 0, y: 120, width: 402, height: 226)

        surface.setNeedsLayout()
        surface.layoutIfNeeded()

        XCTAssertEqual(layer.frame, CGRect(origin: .zero, size: targetSize))
        XCTAssertTrue(layer.animationKeys()?.isEmpty ?? true)
    }

    private func makeDetail(dependencies: AppDependencies) throws -> VideoDetailViewModel {
        let video = try JSONDecoder.bili.decode(VideoItem.self,
            from: Data(#"{"bvid":"BVQualityTransitionProbe","title":"Quality transition probe","cid":1}"#.utf8))
        return VideoDetailViewModel(seedVideo: video, api: dependencies.api,
            libraryStore: dependencies.libraryStore, sessionStore: dependencies.sessionStore,
            sponsorBlockService: dependencies.sponsorBlockService)
    }

    private func makeShellHost(player: PlayerStateViewModel, detail: VideoDetailViewModel,
                               dependencies: AppDependencies, runtime: VideoDetailRuntimeSettingsStore,
                               rotationCoordinator: PlaybackRotationCoordinator = PlaybackRotationCoordinator()) -> VideoDetailShellSurfaceHost {
        VideoDetailShellSurfaceHost(playerViewModel: player, detailViewModel: detail,
            dependencies: dependencies, runtimeSettings: runtime, rotationCoordinator: rotationCoordinator,
            onShowMoreControls: { _ in }, onDismissMoreControls: {}, onRequestFullscreen: {}, onExitFullscreen: {},
            onToggleDanmaku: {}, onShowDanmakuSettings: {})
    }

    private func makeTransitionSnapshot(color: UIColor) -> PlaybackTransitionSnapshot {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 18)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 18))
        }
        return PlaybackTransitionSnapshot(image: image)
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

    private func findDanmakuHost(in view: UIView) -> DanmakuRendererHostView? {
        if let host = view as? DanmakuRendererHostView { return host }
        return view.subviews.lazy.compactMap { self.findDanmakuHost(in: $0) }.first
    }

    private func findView(withIdentifier identifier: String, in view: UIView) -> UIView? {
        if view.accessibilityIdentifier == identifier { return view }
        return view.subviews.lazy.compactMap {
            self.findView(withIdentifier: identifier, in: $0)
        }.first
    }

    private func layerMatchesSurface(_ surface: VideoSurfaceContainerView, size: CGSize) -> Bool {
        let layer = surface.drawableView.layer.sublayers?.compactMap { $0 as? AVPlayerLayer }.first
        return surface.bounds.size == size && surface.drawableView.bounds.size == size
            && layer?.frame.size == size && layer?.videoGravity == .resizeAspect
    }
}
