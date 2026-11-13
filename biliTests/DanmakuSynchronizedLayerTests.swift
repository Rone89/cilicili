import AVFoundation
import XCTest
@testable import bili

/// 同步层弹幕后端的确定性单测：泳道分配、后端选择、物化/回收生命周期。
/// 时间轴驱动的动画由 Core Animation 呈现，这里只断言排程与结构状态。
@MainActor
final class DanmakuSynchronizedLayerTests: XCTestCase {
    // MARK: Lane allocator

    func testLaneAllocatorReusesScrollingLaneAtFortyFivePercent() {
        var allocator = DanmakuSyncLaneAllocator(laneCount: 3)
        let first = allocator.reserveScrollingLane(at: 0, duration: 10, allowsOverlap: true)
        XCTAssertEqual(first, 0)
        // 45% 处（4.5s）泳道 0 即可复用；2s 处尚未到 → 选泳道 1。
        XCTAssertEqual(allocator.reserveScrollingLane(at: 2, duration: 10, allowsOverlap: true), 1)
        XCTAssertEqual(allocator.reserveScrollingLane(at: 4.6, duration: 10, allowsOverlap: true), 0)
        // 已占用泳道返回 nil 由调用方决定丢弃或重叠回退。
    }

    func testLaneAllocatorOverlapFallbackStaysInBoundsWhenAllLanesBusy() {
        var allocator = DanmakuSyncLaneAllocator(laneCount: 2)
        _ = allocator.reserveScrollingLane(at: 0, duration: 10, allowsOverlap: true)
        _ = allocator.reserveScrollingLane(at: 0, duration: 10, allowsOverlap: true)
        // 允许重叠时全忙选最早空闲的一条，永不返回越界。
        let overflow = allocator.reserveScrollingLane(at: 0, duration: 10, allowsOverlap: true)
        XCTAssertNotNil(overflow)
        XCTAssertTrue((0..<2).contains(overflow!))
    }

    func testOverlapDisabledSkipsWhenAllLanesBusy() {
        var allocator = DanmakuSyncLaneAllocator(laneCount: 2)
        XCTAssertNotNil(allocator.reserveScrollingLane(at: 0, duration: 10, allowsOverlap: false))
        XCTAssertNotNil(allocator.reserveScrollingLane(at: 0, duration: 10, allowsOverlap: false))
        // 泳道占满且不允许重叠时丢弃新弹幕，而不是叠上去。
        XCTAssertNil(allocator.reserveScrollingLane(at: 0, duration: 10, allowsOverlap: false))
        // 允许重叠时回退最早空闲泳道（旧行为）。
        XCTAssertNotNil(allocator.reserveScrollingLane(at: 0, duration: 10, allowsOverlap: true))
    }

    func testStaticLanesUseFullDurationAndIndependentPools() {
        var allocator = DanmakuSyncLaneAllocator(laneCount: 3)
        XCTAssertEqual(allocator.reserveTopLane(at: 0, duration: 4, allowsOverlap: true), 0)
        XCTAssertEqual(allocator.reserveTopLane(at: 1, duration: 4, allowsOverlap: true), 1)
        // 顶部泳道占满 4s；底部泳道独立记账，不受顶部影响。
        XCTAssertEqual(allocator.reserveBottomLane(at: 1, duration: 4, allowsOverlap: true), 0)
        XCTAssertEqual(allocator.reserveTopLane(at: 4.1, duration: 4, allowsOverlap: true), 0)
    }

    // MARK: Host selection

    func testHostSelectsRenderersByPreference() {
        let host = DanmakuRendererHostView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        host.selectRenderer(preference: .synchronizedLayer)
        XCTAssertTrue(host.usesSynchronizedLayer)
        XCTAssertFalse(host.usesMetal)

        host.selectRenderer(preference: .danmakuKit)
        XCTAssertFalse(host.usesSynchronizedLayer)
        XCTAssertFalse(host.usesMetal)

        host.selectRenderer(preference: .metal)
        XCTAssertTrue(host.usesMetal)
        XCTAssertFalse(host.usesSynchronizedLayer)
        host.stop()
    }

    // MARK: Materialization lifecycle

    func testAttachPlayerAndApplyMaterializesWindowedItems() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let item = AVPlayerItem(url: URL(string: "https://example.invalid/danmaku-sync-probe.m4s")!)
        let player = AVPlayer(playerItem: item)
        let view = DanmakuSynchronizedLayerView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        let window = UIWindow(windowScene: scene)
        window.isHidden = false
        window.rootViewController = UIViewController()
        window.rootViewController?.view.addSubview(view)
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        let configuration = DanmakuOverlayConfiguration(
            items: [
                DanmakuItem(id: "a", time: 0.2, mode: 1, fontSize: 25, color: 0xFFFFFF, text: "同步层弹幕"),
                DanmakuItem(id: "b", time: 1.4, mode: 5, fontSize: 25, color: 0xFFFFFF, text: "顶部弹幕"),
            ],
            itemsRevision: 1,
            currentTime: 0,
            isPlaying: true,
            playbackRate: 1,
            isEnabled: true,
            hasPresentedPlayback: true,
            isLoadShedding: false,
            settings: DanmakuSettings(),
            topInset: 0,
            bottomInset: 0
        )
        view.apply(configuration: configuration)
        XCTAssertFalse(view.isSyncLayerInstalled, "未提供播放器时不挂同步层")

        view.attachPlaybackPlayer(player)
        XCTAssertTrue(view.isSyncLayerInstalled, "attach 后应按 currentItem 挂同步层")
        // 排程前瞻窗口 2s：0.2s 滚动弹幕与 1.4s 顶部弹幕都在窗口内，应立即物化。
        XCTAssertEqual(view.activeDanmakuCount, 2)

        let pooled = view.pooledLayerCount
        view.stop()
        XCTAssertEqual(view.activeDanmakuCount, 0)
        XCTAssertFalse(view.isSyncLayerInstalled)
        XCTAssertGreaterThanOrEqual(view.pooledLayerCount, pooled)
    }

    func testDisabledConfigurationTearsDownRendering() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let item = AVPlayerItem(url: URL(string: "https://example.invalid/danmaku-sync-probe.m4s")!)
        let player = AVPlayer(playerItem: item)
        let view = DanmakuSynchronizedLayerView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        let window = UIWindow(windowScene: scene)
        window.isHidden = false
        window.rootViewController = UIViewController()
        window.rootViewController?.view.addSubview(view)
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        view.attachPlaybackPlayer(player)
        view.apply(configuration: DanmakuOverlayConfiguration(
            items: [DanmakuItem(id: "a", time: 0, mode: 1, fontSize: 25, color: 0xFFFFFF, text: "x")],
            itemsRevision: 1,
            currentTime: 0,
            isPlaying: true,
            playbackRate: 1,
            isEnabled: false,
            hasPresentedPlayback: true,
            isLoadShedding: false,
            settings: DanmakuSettings(),
            topInset: 0,
            bottomInset: 0
        ))
        XCTAssertFalse(view.isSyncLayerInstalled)
        XCTAssertEqual(view.activeDanmakuCount, 0)
    }
}
