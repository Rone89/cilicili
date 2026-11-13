import AVFoundation
import XCTest
@testable import bili

/// 同步层弹幕后端的确定性单测：泳道分配、后端选择、物化/回收生命周期。
/// 时间轴驱动的动画由 Core Animation 呈现，这里只断言排程与结构状态。
@MainActor
final class DanmakuSynchronizedLayerTests: XCTestCase {
    // MARK: Lane allocator

    func testScrollingLaneReusesOnlyAfterEntrySweepPassesTail() {
        var allocator = DanmakuSyncLaneAllocator(laneCount: 3)
        // 位图 80 / 画布 400 / 时长 7.2：进场点扫过尾端 ≈ 开始 + 1.2s（远早于旧 45% 比例）。
        let reusable = 7.2 * 80 / (400 + 80)
        XCTAssertEqual(allocator.reserveScrollingLane(at: 0, reusableAt: reusable, allowsOverlap: true), 0)
        // 尾端被扫过前不得复用 → 选泳道 1。
        XCTAssertEqual(allocator.reserveScrollingLane(at: reusable - 0.05, reusableAt: 5, allowsOverlap: true), 1)
        // 扫过后泳道 0 即可复用。
        XCTAssertEqual(allocator.reserveScrollingLane(at: reusable + 0.05, reusableAt: 5, allowsOverlap: true), 0)
    }

    func testLaneAllocatorOverlapFallbackStaysInBoundsWhenAllLanesBusy() {
        var allocator = DanmakuSyncLaneAllocator(laneCount: 2)
        _ = allocator.reserveScrollingLane(at: 0, reusableAt: 10, allowsOverlap: true)
        _ = allocator.reserveScrollingLane(at: 0, reusableAt: 10, allowsOverlap: true)
        // 允许重叠时全忙选最早空闲的一条，永不返回越界。
        let overflow = allocator.reserveScrollingLane(at: 0, reusableAt: 10, allowsOverlap: true)
        XCTAssertNotNil(overflow)
        XCTAssertTrue((0..<2).contains(overflow!))
    }

    func testOverlapDisabledSkipsWhenAllLanesBusy() {
        var allocator = DanmakuSyncLaneAllocator(laneCount: 2)
        XCTAssertNotNil(allocator.reserveScrollingLane(at: 0, reusableAt: 10, allowsOverlap: false))
        XCTAssertNotNil(allocator.reserveScrollingLane(at: 0, reusableAt: 10, allowsOverlap: false))
        // 泳道占满且不允许重叠时交给调用方排队（返回 nil），而不是叠上去。
        XCTAssertNil(allocator.reserveScrollingLane(at: 0, reusableAt: 10, allowsOverlap: false))
        // 允许重叠时回退最早空闲泳道（旧行为）。
        XCTAssertNotNil(allocator.reserveScrollingLane(at: 0, reusableAt: 10, allowsOverlap: true))
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

    // MARK: Scheduling backpressure（竖屏少泳道下的连续进场）

    /// 泳道占满时弹幕排队等下一拍重试，而不是被永久丢弃；泳道释放后继续进场。
    /// 400×200 画布 + 100% 区域 = 6 条滚动泳道；10 字文本泳道占用 ≈ 2.3s。
    func testBusyLanesQueueInsteadOfDropping() throws {
        let (view, window) = try makeAttachedView(width: 400, height: 200)
        defer { window.isHidden = true }

        let longText = "弹幕排队占位测试文本"
        let items = (0..<12).map { index in
            DanmakuItem(id: "queue-\(index)", time: 0.4, mode: 1, fontSize: 25, color: 0xFFFFFF, text: longText)
        }
        view.apply(configuration: Self.configuration(
            items: items,
            settings: DanmakuSettings(danmakuKit: .init(displayArea: .full))
        ))
        // 首拍只放进 6 条泳道；其余 6 条排队（未消耗、未丢弃）。
        XCTAssertEqual(view.activeDanmakuCount, 6)
        XCTAssertEqual(view.debugPendingDanmakuCount, 6)

        // 泳道仍被占（尾端 2.69s 后才被扫过）：排队继续等待，不丢弃。
        view.debugScheduleForTesting(at: 2.0)
        XCTAssertEqual(view.activeDanmakuCount, 6)
        XCTAssertEqual(view.debugPendingDanmakuCount, 6)

        // 泳道释放（2.69s ≤ 2.8s 且仍在 3s 排队宽限内）：排队的 6 条继续进场。
        view.debugScheduleForTesting(at: 2.8)
        XCTAssertEqual(view.activeDanmakuCount, 12)
        XCTAssertEqual(view.debugPendingDanmakuCount, 0)

        view.debugScheduleForTesting(at: 4.0)
        XCTAssertEqual(view.activeDanmakuCount, 12)
        XCTAssertEqual(view.debugPendingDanmakuCount, 0)
    }

    /// 迟到弹幕（重放回看窗口内）从右缘进场：动画 beginTime 钳制到当前媒体时刻。
    func testLateItemEntersFromRightEdgeWithClampedBeginTime() throws {
        let (view, window) = try makeAttachedView(width: 400, height: 200)
        defer { window.isHidden = true }

        view.apply(configuration: Self.configuration(
            items: [DanmakuItem(id: "late", time: 4.5, mode: 1, fontSize: 25, color: 0xFFFFFF, text: "迟到弹幕")],
            settings: DanmakuSettings(danmakuKit: .init(displayArea: .full))
        ))
        XCTAssertEqual(view.activeDanmakuCount, 0)

        // 0.5s 迟到（宽限 2.5s 内）：立即进场，beginTime = 当前时刻而非过去的 4.5s。
        view.debugScheduleForTesting(at: 5.0)
        XCTAssertEqual(view.activeDanmakuCount, 1)
        let beginTime = try XCTUnwrap(view.debugFirstScrollAnimationBeginTime)
        XCTAssertEqual(beginTime, 5.0, accuracy: 0.001)
    }

    /// 超过排队宽限的弹幕放弃展示，游标前进（不堆积）。
    func testVeryLateItemIsSkipped() throws {
        let (view, window) = try makeAttachedView(width: 400, height: 200)
        defer { window.isHidden = true }

        view.apply(configuration: Self.configuration(
            items: [DanmakuItem(id: "stale", time: 4.5, mode: 1, fontSize: 25, color: 0xFFFFFF, text: "过期弹幕")],
            settings: DanmakuSettings(danmakuKit: .init(displayArea: .full))
        ))
        view.debugScheduleForTesting(at: 8.0)
        XCTAssertEqual(view.activeDanmakuCount, 0)
        XCTAssertEqual(view.debugPendingDanmakuCount, 0)
    }

    // MARK: Helpers

    private func makeAttachedView(width: CGFloat, height: CGFloat) throws -> (DanmakuSynchronizedLayerView, UIWindow) {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let item = AVPlayerItem(url: URL(string: "https://example.invalid/danmaku-sync-probe.m4s")!)
        let player = AVPlayer(playerItem: item)
        let view = DanmakuSynchronizedLayerView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        let window = UIWindow(windowScene: scene)
        window.isHidden = false
        window.rootViewController = UIViewController()
        window.rootViewController?.view.addSubview(view)
        view.attachPlaybackPlayer(player)
        return (view, window)
    }

    private static func configuration(
        items: [DanmakuItem],
        settings: DanmakuSettings
    ) -> DanmakuOverlayConfiguration {
        DanmakuOverlayConfiguration(
            items: items,
            itemsRevision: 1,
            currentTime: 0,
            isPlaying: true,
            playbackRate: 1,
            isEnabled: true,
            hasPresentedPlayback: true,
            isLoadShedding: false,
            settings: settings,
            topInset: 0,
            bottomInset: 0
        )
    }
}
