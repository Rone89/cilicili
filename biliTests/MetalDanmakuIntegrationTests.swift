import MetalKit
import XCTest
@testable import bili

@MainActor
final class MetalDanmakuIntegrationTests: XCTestCase {
    private final class WeakView {
        weak var value: UIView?
        init(_ value: UIView?) { self.value = value }
    }

    private func configuration(items: [DanmakuItem], time: Double = 1, revision: Int = 1,
                               playing: Bool = false) -> DanmakuOverlayConfiguration {
        DanmakuOverlayConfiguration(items: items, itemsRevision: revision, currentTime: time,
            isPlaying: playing, playbackRate: 1, isEnabled: true, hasPresentedPlayback: true,
            isLoadShedding: false, settings: DanmakuSettings(hidesInPortrait: false,
                danmakuKit: DanmakuKitRenderSettings(displayArea: .full, allowsDanmakuOverlap: true)),
            topInset: 0, bottomInset: 0)
    }
    private func items(count: Int) -> [DanmakuItem] {
        (0..<count).map { DanmakuItem(id: "fixture-\($0)", time: 0, mode: 1, fontSize: 25,
                                    color: 0xFFFFFF, text: "测试 ABC \($0)") }
    }

    func testCollapsedHostPreservesDanmakuKitTracksWithoutViewportRebuild() throws {
        let diagnostics = DanmakuRendererDiagnostics.shared
        diagnostics.start()
        let host = DanmakuRendererHostView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        defer { host.stop(); diagnostics.stop() }
        host.setLogicalCanvasSize(host.bounds.size)
        host.selectRenderer(metalEnabled: false)
        host.layoutIfNeeded()
        let child = try XCTUnwrap(host.subviews.first as? DanmakuKitOverlayView)
        child.layoutIfNeeded()
        host.apply(configuration: configuration(items: items(count: 10)))
        let rebuilds = diagnostics.danmakuKitSummary.rebuilds
        XCTAssertGreaterThan(rebuilds, 0)

        for height in [500.0, 350, 220, 54, 600] {
            host.frame.size.height = height
            host.layoutIfNeeded()
            child.layoutIfNeeded()
            XCTAssertTrue(host.subviews.first === child)
            XCTAssertEqual(child.frame, CGRect(x: 0, y: 0, width: 390, height: 600))
            XCTAssertEqual(diagnostics.danmakuKitSummary.rebuilds, rebuilds)
            XCTAssertTrue(host.clipsToBounds)
        }
        // A genuine canvas change still updates the tracks.
        host.setLogicalCanvasSize(CGSize(width: 844, height: 390))
        child.layoutIfNeeded()
        XCTAssertGreaterThan(diagnostics.danmakuKitSummary.rebuilds, rebuilds)
    }

    func testCollapsedHostPreservesMetalFramesAndTimelineThenSupportsSeek() throws {
        let host = DanmakuRendererHostView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        defer { host.stop() }
        host.setLogicalCanvasSize(host.bounds.size)
        host.selectRenderer(metalEnabled: true)
        guard host.usesMetal else { throw XCTSkip("Metal unavailable") }
        host.layoutIfNeeded()
        let child = try XCTUnwrap(host.subviews.first as? MetalDanmakuView)
        child.layoutIfNeeded()
        let fixture = items(count: 10) + [
            DanmakuItem(id: "top", time: 0, mode: 5, fontSize: 25, color: 0xFFFFFF, text: "顶部"),
            DanmakuItem(id: "bottom", time: 0, mode: 4, fontSize: 25, color: 0xFFFFFF, text: "底部")
        ]
        host.apply(configuration: configuration(items: fixture))
        let frames = child.debugFrames(at: 1)
        XCTAssertNotNil(frames["top"])
        XCTAssertNotNil(frames["bottom"])
        XCTAssertFalse(frames.isEmpty)
        let revision = child.debugTimelineRevision
        let rasterizations = child.debugRenderer.atlas.rasterizationCount

        for height in [500.0, 350, 220, 54, 600] {
            host.frame.size.height = height
            host.layoutIfNeeded()
            child.layoutIfNeeded()
            XCTAssertTrue(host.subviews.first === child)
            XCTAssertEqual(child.bounds.size, CGSize(width: 390, height: 600))
            XCTAssertEqual(child.debugFrames(at: 1), frames)
            XCTAssertEqual(child.debugTimelineRevision, revision)
            XCTAssertEqual(child.debugRenderer.atlas.rasterizationCount, rasterizations)
        }
        XCTAssertNotEqual(child.debugFrames(at: 2), frames, "Media time must still move the glyphs")
        host.frame.size.height = 220
        host.layoutIfNeeded()
        host.synchronizePlaybackTime(30, force: true)
        XCTAssertEqual(child.debugActiveCount, 0, "Expired entries must not return on expansion")
        host.frame.size.height = 600
        host.layoutIfNeeded()
        XCTAssertEqual(child.debugActiveCount, 0)
        host.synchronizePlaybackTime(1, force: true)
        XCTAssertEqual(child.debugFrames(at: 1), frames, "Backward seek must reconstruct at logical size")
        host.setLogicalCanvasSize(CGSize(width: 844, height: 390))
        child.layoutIfNeeded()
        XCTAssertEqual(child.bounds.size, CGSize(width: 844, height: 390))
        XCTAssertNotEqual(child.debugFrames(at: 1), frames)
    }

    func testHostWithoutCanvasOverrideFollowsBoundsAndRejectsInvalidSizes() throws {
        let host = DanmakuRendererHostView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        defer { host.stop() }
        host.selectRenderer(metalEnabled: false)
        let child = try XCTUnwrap(host.subviews.first)
        host.frame.size.height = 220
        host.layoutIfNeeded()
        XCTAssertEqual(child.frame, host.bounds)
        host.setLogicalCanvasSize(CGSize(width: 390, height: 600))
        XCTAssertEqual(child.frame.size.height, 600)
        for invalid in [CGSize.zero, CGSize(width: CGFloat.nan, height: 600),
                        CGSize(width: 390, height: CGFloat.infinity), CGSize(width: -1, height: 600)] {
            host.setLogicalCanvasSize(invalid)
            XCTAssertEqual(child.frame, host.bounds)
        }
    }

    func testRendererSwitchWhileCollapsedKeepsCanvasAndReleasesPreviousChild() throws {
        let host = DanmakuRendererHostView(frame: CGRect(x: 0, y: 0, width: 390, height: 220))
        defer { host.stop() }
        host.setLogicalCanvasSize(CGSize(width: 390, height: 600))
        host.selectRenderer(metalEnabled: false)
        let previous = try XCTUnwrap(host.subviews.first)
        host.selectRenderer(metalEnabled: true)
        XCTAssertNil(previous.superview)
        XCTAssertEqual(host.subviews.count, 1)
        XCTAssertEqual(host.subviews.first?.frame, CGRect(x: 0, y: 0, width: 390, height: 600))
        host.selectRenderer(metalEnabled: false)
        XCTAssertEqual(host.subviews.count, 1)
        XCTAssertTrue(host.subviews.first is DanmakuKitOverlayView)
        XCTAssertEqual(host.subviews.first?.frame.size.height, 600)
        host.setLogicalCanvasSize(nil)
        XCTAssertEqual(host.subviews.first?.frame, host.bounds)
        host.stop()
        XCTAssertTrue(host.subviews.isEmpty)
    }

    func testExperimentDefaultsOffAndPersistsAcrossStoreRecreation() {
        let suite = "metal-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LibraryStore(userDefaults: defaults)
        XCTAssertFalse(store.metalDanmakuRendererExperimentEnabled)
        store.setMetalDanmakuRendererExperimentEnabled(true)
        XCTAssertTrue(LibraryStore(userDefaults: defaults).metalDanmakuRendererExperimentEnabled)
        store.setMetalDanmakuRendererExperimentEnabled(false)
        XCTAssertFalse(LibraryStore(userDefaults: defaults).metalDanmakuRendererExperimentEnabled)
    }

    func testHostSwitchHasExactlyOneRendererAndOffRestoresDanmakuKit() async throws {
        let host = DanmakuRendererHostView(frame: CGRect(x: 0, y: 0, width: 900, height: 400))
        defer { host.stop() }
        host.selectRenderer(metalEnabled: false)
        host.apply(configuration: configuration(items: items(count: 10)))
        XCTAssertEqual(host.subviews.count, 1)
        XCTAssertTrue(host.subviews.first is DanmakuKitOverlayView)
        let previous = WeakView(host.subviews.first)
        host.selectRenderer(metalEnabled: true)
        XCTAssertNil(previous.value?.superview)
        // Core Animation may retain the retired layer until its transaction drains.
        let releaseLimit = ContinuousClock.now.advanced(by: .seconds(1))
        while previous.value != nil, ContinuousClock.now < releaseLimit {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertNil(previous.value)
        XCTAssertEqual(host.subviews.count, 1)
        guard host.usesMetal else { throw XCTSkip("Metal unavailable on this runtime") }
        host.apply(configuration: configuration(items: items(count: 10)))
        let metal = try XCTUnwrap(host.subviews.first as? MetalDanmakuView)
        XCTAssertFalse(metal.metalView.isOpaque)
        XCTAssertEqual(metal.metalView.clearColor.alpha, 0)
        XCTAssertFalse(metal.isUserInteractionEnabled)
        host.selectRenderer(metalEnabled: false)
        XCTAssertTrue(metal.metalView.isPaused)
        XCTAssertEqual(metal.debugActiveCount, 0)
        XCTAssertEqual(host.subviews.count, 1)
        XCTAssertTrue(host.subviews.first is DanmakuKitOverlayView)
    }

    func testRepeatedCreateSeekResizeStopKeepsAtlasAndSceneBounded() throws {
        for _ in 0..<10 {
            guard let view = MetalDanmakuView.make() else { throw XCTSkip("Metal unavailable") }
            view.frame = CGRect(x: 0, y: 0, width: 900, height: 400)
            view.debugMaximumActiveCount = 300
            view.layoutIfNeeded()
            view.apply(configuration: configuration(items: items(count: 300)))
            XCTAssertEqual(view.debugActiveCount, 300)
            XCTAssertLessThanOrEqual(view.debugRenderer.atlas.textures.count, 4)
            let rasterizations = view.debugRenderer.atlas.rasterizationCount
            view.synchronizePlaybackTime(3, force: true)
            view.synchronizePlaybackTime(1, force: true)
            XCTAssertEqual(view.debugRenderer.atlas.rasterizationCount, rasterizations)
            view.setLayoutTransitioning(true)
            XCTAssertTrue(view.metalView.isHidden)
            view.frame.size = CGSize(width: 400, height: 900)
            view.layoutIfNeeded()
            view.setLayoutTransitioning(false)
            XCTAssertEqual(view.debugActiveCount, 300)
            view.stop()
            XCTAssertEqual(view.debugActiveCount, 0)
            XCTAssertEqual(view.debugRenderer.atlas.textures.count, 0)
            XCTAssertTrue(view.metalView.isPaused)
        }
    }

    func testWindowRefreshKeepsAlreadyScrollingItemsVisible() throws {
        guard let view = MetalDanmakuView.make() else { throw XCTSkip("Metal unavailable") }
        defer { view.stop() }
        view.frame = CGRect(x: 0, y: 0, width: 900, height: 400)
        view.debugMaximumActiveCount = 24
        view.layoutIfNeeded()

        let existing = (0..<24).map { index in
            DanmakuItem(id: "existing-\(index)", time: 1, mode: 1, fontSize: 25,
                        color: 0xFFFFFF, text: "existing \(index)")
        }
        view.apply(configuration: configuration(items: existing, time: 1, revision: 1))
        let activeBeforeRefresh = view.debugActiveItemIDs
        XCTAssertEqual(activeBeforeRefresh.count, 24)

        let newlyVisible = (0..<6).map { index in
            DanmakuItem(id: "new-\(index)", time: 1.25, mode: 1, fontSize: 25,
                        color: 0xFFFFFF, text: "new \(index)")
        }
        view.apply(configuration: configuration(items: existing + newlyVisible, time: 1.5, revision: 2))

        XCTAssertEqual(view.debugActiveItemIDs, activeBeforeRefresh)
        XCTAssertEqual(view.debugActiveCount, 24)
    }

    func testActualShaderRendersDensityFixturesWithTransparentBackgroundAndFewDrawCalls() throws {
        for count in [10, 50, 100, 300, 600] {
            guard let view = MetalDanmakuView.make() else { throw XCTSkip("Metal unavailable") }
            defer { view.stop() }
            let size = CGSize(width: 900, height: 400)
            view.frame = CGRect(origin: .zero, size: size)
            view.debugMaximumActiveCount = count
            view.layoutIfNeeded()
            view.apply(configuration: configuration(items: items(count: count)))
            XCTAssertEqual(view.debugActiveCount, count)
            let texture = try XCTUnwrap(view.debugRenderer.debugRenderOffscreen(size: size, time: 1))
            let first = read(texture)
            let alpha = stride(from: 3, to: first.count, by: 4).map { first[$0] }
            XCTAssertTrue(alpha.contains { $0 > 0 }, "GPU must draw glyph pixels at density \(count)")
            XCTAssertTrue(alpha.contains(0), "Video background must stay transparent")
            XCTAssertGreaterThan(view.debugRenderer.drawCalls, 0)
            XCTAssertLessThanOrEqual(view.debugRenderer.drawCalls, 4)
            print("Metal fixture density=\(count) active=\(view.debugActiveCount) pages=\(view.debugRenderer.atlas.textures.count) drawCalls=\(view.debugRenderer.drawCalls)")
            let repeated = try XCTUnwrap(view.debugRenderer.debugRenderOffscreen(size: size, time: 1))
            XCTAssertEqual(read(repeated), first, "Frozen media time must produce identical pixels")
            let moved = try XCTUnwrap(view.debugRenderer.debugRenderOffscreen(size: size, time: 3))
            XCTAssertNotEqual(read(moved), first, "The shader must compute movement from absolute media time")
        }
    }

    private func read(_ texture: MTLTexture) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        bytes.withUnsafeMutableBytes {
            texture.getBytes($0.baseAddress!, bytesPerRow: texture.width * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
        }
        return bytes
    }

    func testMTKViewActuallySubmitsFramesAndPausesStopsOnWindowDetach() async throws {
        guard let view = MetalDanmakuView.make() else { throw XCTSkip("Metal unavailable") }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            throw XCTSkip("No window scene in this runtime")
        }
        let diagnostics = DanmakuRendererDiagnostics()
        view.debugDiagnostics = diagnostics
        diagnostics.start()
        defer { diagnostics.stop() }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 900, height: 400)
        let controller = UIViewController()
        window.rootViewController = controller
        controller.view.addSubview(view)
        view.frame = window.bounds
        window.isHidden = false
        defer { view.stop(); window.isHidden = true }
        view.layoutIfNeeded()
        view.apply(configuration: configuration(items: items(count: 10), playing: true))
        let limit = ContinuousClock.now.advanced(by: .seconds(3))
        while view.debugRenderer.submittedFrames < 3, ContinuousClock.now < limit {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertGreaterThanOrEqual(view.debugRenderer.submittedFrames, 3)
        XCTAssertFalse(view.metalView.isPaused)
        XCTAssertEqual(view.debugManualRefreshCount, 0)
        XCTAssertEqual(diagnostics.metalSummary.manualRefreshFrames, 0)
        XCTAssertGreaterThanOrEqual(diagnostics.metalSummary.automaticFrames, 3)
        // Clock/configuration updates must not synchronously submit extra frames
        // while MTKView already owns the active draw loop.
        let submitted = view.debugRenderer.submittedFrames
        for _ in 0..<20 {
            view.apply(configuration: configuration(items: items(count: 10), time: 1.5, playing: true))
        }
        view.synchronizePlaybackTime(2, force: true)
        view.setLayoutTransitioning(true)
        view.setLayoutTransitioning(false)
        XCTAssertEqual(view.debugRenderer.submittedFrames, submitted)
        XCTAssertEqual(view.debugManualRefreshCount, 0)

        view.apply(configuration: configuration(items: items(count: 10), time: 1.5, playing: false))
        XCTAssertTrue(view.metalView.isPaused)
        XCTAssertEqual(view.debugManualRefreshCount, 1, "Paused updates still need a single-frame refresh")
        view.synchronizePlaybackTime(2, force: true)
        XCTAssertEqual(view.debugManualRefreshCount, 2, "Paused seek must refresh its target frame")
        XCTAssertGreaterThan(diagnostics.metalSummary.manualRefreshFrames, 0)
        view.apply(configuration: configuration(items: items(count: 10), time: 2, playing: true))
        XCTAssertFalse(view.metalView.isPaused)
        XCTAssertEqual(view.debugManualRefreshCount, 2, "Resume uses the scheduled loop")
        view.removeFromSuperview()
        XCTAssertTrue(view.metalView.isPaused)
        view.apply(configuration: configuration(items: items(count: 10), time: 3, playing: false))
        XCTAssertEqual(view.debugManualRefreshCount, 2, "Detached surfaces must not draw")
        view.stop()
        XCTAssertEqual(view.debugActiveCount, 0)
    }
}
