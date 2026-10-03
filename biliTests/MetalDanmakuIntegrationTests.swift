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
        view.apply(configuration: configuration(items: items(count: 10), time: 1.5, playing: false))
        XCTAssertTrue(view.metalView.isPaused)
        view.apply(configuration: configuration(items: items(count: 10), time: 1.5, playing: true))
        XCTAssertFalse(view.metalView.isPaused)
        view.removeFromSuperview()
        XCTAssertTrue(view.metalView.isPaused)
        view.stop()
        XCTAssertEqual(view.debugActiveCount, 0)
    }
}
