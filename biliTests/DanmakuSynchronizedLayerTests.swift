import AVFoundation
import XCTest
@testable import bili

/// 同步层弹幕后端的确定性单测：泳道分配、后端选择、物化/回收生命周期。
/// 时间轴驱动的动画由 Core Animation 呈现，这里只断言排程与结构状态。
@MainActor
final class DanmakuSynchronizedLayerTests: XCTestCase {
    // MARK: Lane allocator

    func testScrollingLaneReusesOnlyAfterEntrySweepPassesTail() {
        // 单泳道：精确验证“尾端被进场点扫过”这一复用门控。
        var allocator = DanmakuSyncLaneAllocator(laneCount: 1)
        let reusable = 7.2 * 80 / (400 + 80)
        XCTAssertEqual(allocator.reserveScrollingLane(at: 0, reusableAt: reusable, allowsOverlap: false), 0)
        // 尾端未扫过前不得复用 → 无可用泳道。
        XCTAssertNil(allocator.reserveScrollingLane(at: reusable - 0.05, reusableAt: 5, allowsOverlap: false))
        // 扫过后可复用。
        XCTAssertEqual(allocator.reserveScrollingLane(at: reusable + 0.05, reusableAt: 5, allowsOverlap: false), 0)
    }

    func testScrollingLanesRotateToSpreadBullets() {
        // 全部空闲时连续分配应轮转铺开到不同泳道，而不是永远挤在最上面一条。
        var allocator = DanmakuSyncLaneAllocator(laneCount: 4)
        var lanes: [Int] = []
        for _ in 0..<4 {
            if let lane = allocator.reserveScrollingLane(at: 0, reusableAt: 10, allowsOverlap: false) {
                lanes.append(lane)
            }
        }
        XCTAssertEqual(Set(lanes).count, 4, "连续分配应铺开到全部泳道")
        XCTAssertNil(
            allocator.reserveScrollingLane(at: 0, reusableAt: 10, allowsOverlap: false),
            "泳道占满且不允许重叠时应交给调用方排队"
        )
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

    func testOverlapFallbackKeepsLongerLaneReservation() {
        var allocator = DanmakuSyncLaneAllocator(laneCount: 1)
        _ = allocator.reserveScrollingLane(at: 0, reusableAt: 10, allowsOverlap: false)
        _ = allocator.reserveScrollingLane(at: 1, reusableAt: 2, allowsOverlap: true)
        XCTAssertEqual(allocator.scrollingFreeAt[0], 10)

        _ = allocator.reserveTopLane(at: 0, duration: 10, allowsOverlap: false)
        _ = allocator.reserveTopLane(at: 0, duration: 10, allowsOverlap: false)
        _ = allocator.reserveTopLane(at: 1, duration: 1, allowsOverlap: true)
        XCTAssertEqual(allocator.topFreeAt[0], 10)
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
    /// 400×200 画布 + 100% 区域 = 6 条滚动泳道；10 字文本（位图 ≈187pt）
    /// 时长 (400+187)/124 ≈ 4.7s，尾端被扫过 ≈ 开始 + 1.5s。
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

        // 泳道仍被占（尾端 1.91s 后才被扫过）：排队继续等待，不丢弃。
        view.debugScheduleForTesting(at: 1.0)
        XCTAssertEqual(view.activeDanmakuCount, 6)
        XCTAssertEqual(view.debugPendingDanmakuCount, 6)

        // 泳道释放（1.91s ≤ 2.0s 且仍在 3s 排队宽限内）：排队的 6 条继续进场。
        view.debugScheduleForTesting(at: 2.0)
        XCTAssertEqual(view.activeDanmakuCount, 12)
        XCTAssertEqual(view.debugPendingDanmakuCount, 0)
        let beginsAfterRetry = view.debugScrollAnimationBeginTimes
        XCTAssertEqual(beginsAfterRetry.count, 12)
        for (actual, expected) in zip(beginsAfterRetry.suffix(6), [2.0, 2.05, 2.10, 2.15, 2.20, 2.25]) {
            XCTAssertEqual(actual, expected, accuracy: 0.001)
        }

        view.debugScheduleForTesting(at: 4.0)
        XCTAssertEqual(view.activeDanmakuCount, 12)
        XCTAssertEqual(view.debugPendingDanmakuCount, 0)
    }

    /// Same-time rolling comments should enter in small, deterministic steps.
    /// A timestamp already separated from the burst keeps its original media start.
    func testBunchedRollingStartsAreSpacedWithoutMovingIsolatedTimestamp() throws {
        let (view, window) = try makeAttachedView(width: 400, height: 200)
        defer { window.isHidden = true }

        view.apply(configuration: Self.configuration(
            items: [
                DanmakuItem(id: "burst-a", time: 0.4, mode: 1, fontSize: 25, color: 0xFFFFFF, text: "同刻弹幕一"),
                DanmakuItem(id: "burst-b", time: 0.4, mode: 1, fontSize: 25, color: 0xFFFFFF, text: "同刻弹幕二"),
                DanmakuItem(id: "burst-c", time: 0.4, mode: 1, fontSize: 25, color: 0xFFFFFF, text: "同刻弹幕三"),
                DanmakuItem(id: "isolated", time: 0.8, mode: 1, fontSize: 25, color: 0xFFFFFF, text: "独立时间戳"),
            ],
            settings: DanmakuSettings(danmakuKit: .init(displayArea: .full))
        ))

        let begins = view.debugScrollAnimationBeginTimes
        XCTAssertEqual(begins.count, 4)
        for (actual, expected) in zip(begins, [0.4, 0.45, 0.5, 0.8]) {
            XCTAssertEqual(actual, expected, accuracy: 0.001)
        }
    }

    func testOverlapAllowedStillSpreadsBunchedRollingStarts() throws {
        let (view, window) = try makeAttachedView(width: 400, height: 200)
        defer { window.isHidden = true }

        let items = (0..<7).map { index in
            DanmakuItem(id: "overlap-\(index)", time: 0.4, mode: 1, fontSize: 25, color: 0xFFFFFF, text: "允许重叠弹幕 \(index)")
        }
        view.apply(configuration: Self.configuration(
            items: items,
            settings: DanmakuSettings(danmakuKit: .init(
                displayArea: .full,
                allowsDanmakuOverlap: true
            ))
        ))

        let begins = view.debugScrollAnimationBeginTimes
        XCTAssertEqual(view.activeDanmakuCount, 7)
        XCTAssertEqual(begins.count, 7)
        for pair in zip(begins, begins.dropFirst()) {
            XCTAssertGreaterThanOrEqual(pair.1 - pair.0, 0.049)
        }
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

    /// A seek rebuild clears old scheduled starts, so replayed comments aren't held
    /// behind entries that belonged to the pre-seek media timeline.
    func testTimelineResynchronizationResetsRollingStartSpacing() throws {
        let (view, window) = try makeAttachedView(width: 400, height: 200)
        defer { window.isHidden = true }

        view.apply(configuration: Self.configuration(
            items: [
                DanmakuItem(id: "replay-a", time: 0.4, mode: 1, fontSize: 25, color: 0xFFFFFF, text: "重放弹幕一"),
                DanmakuItem(id: "replay-b", time: 0.4, mode: 1, fontSize: 25, color: 0xFFFFFF, text: "重放弹幕二"),
                DanmakuItem(id: "future-a", time: 2.4, mode: 1, fontSize: 25, color: 0xFFFFFF, text: "未来弹幕一"),
                DanmakuItem(id: "future-b", time: 2.4, mode: 1, fontSize: 25, color: 0xFFFFFF, text: "未来弹幕二"),
            ],
            settings: DanmakuSettings(danmakuKit: .init(displayArea: .full))
        ))
        view.debugScheduleForTesting(at: 0.5)
        let beginsBeforeSeek = view.debugScrollAnimationBeginTimes
        XCTAssertEqual(beginsBeforeSeek.count, 4)
        for (actual, expected) in zip(beginsBeforeSeek, [0.4, 0.45, 2.4, 2.45]) {
            XCTAssertEqual(actual, expected, accuracy: 0.001)
        }

        view.debugResynchronizeForTesting(at: 0.5)
        let replayBegins = view.debugScrollAnimationBeginTimes
        XCTAssertEqual(replayBegins.count, 4)
        for (actual, expected) in zip(replayBegins.prefix(2), [0.5, 0.55]) {
            XCTAssertEqual(actual, expected, accuracy: 0.001)
        }
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

    // MARK: Dedup（窗口重发后游标回退不得重复放置）

    /// 生产链路约每 8s 重发窗口，新物品并入会触发游标回退重扫。
    /// 已物化的物品必须被跳过，否则同一句弹幕会重复进场并叠在原弹幕上。
    func testCursorRewindDoesNotRePlaceMaterializedItems() throws {
        let (view, window) = try makeAttachedView(width: 400, height: 200)
        defer { window.isHidden = true }

        let base = [
            DanmakuItem(id: "a", time: 0.2, mode: 1, fontSize: 25, color: 0xFFFFFF, text: "第一句"),
            DanmakuItem(id: "b", time: 1.4, mode: 1, fontSize: 25, color: 0xFFFFFF, text: "第二句"),
        ]
        view.apply(configuration: Self.configuration(
            items: base,
            settings: DanmakuSettings(danmakuKit: .init(displayArea: .full))
        ))
        XCTAssertEqual(view.activeDanmakuCount, 2)

        // 窗口推进：新物品加入使 merged != current → 触发 positionCursor 回退。
        let withNew = base + [
            DanmakuItem(id: "c", time: 3.0, mode: 1, fontSize: 25, color: 0xFFFFFF, text: "第三句"),
        ]
        view.apply(configuration: Self.configuration(
            items: withNew,
            settings: DanmakuSettings(danmakuKit: .init(displayArea: .full))
        ))
        // 回退后重扫：已物化的 a/b 不得重复放置（c 在 2s 前瞻外）。
        view.debugScheduleForTesting(at: 0)
        XCTAssertEqual(view.activeDanmakuCount, 2, "已上屏弹幕被重复放置会造成重叠")
    }

    // MARK: Display area（显示区域占比 → 滚动泳道数）

    /// 竖屏生产几何 430×242、topInset 8 / bottomInset 54 → 内容区高 180。
    /// 泳道高 30 时，占比 0.25/0.5/0.75/1.0 应分别解析出 1/3/4/6 条滚动泳道。
    func testDisplayAreaFractionScalesScrollLaneCount() {
        let view = DanmakuSynchronizedLayerView(frame: CGRect(x: 0, y: 0, width: 430, height: 242))
        let expected: [(Double, Int)] = [(0.25, 1), (0.5, 3), (0.75, 4), (1.0, 6)]
        for (fraction, lanes) in expected {
            view.apply(configuration: DanmakuOverlayConfiguration(
                items: [],
                itemsRevision: 1,
                currentTime: 0,
                isPlaying: true,
                playbackRate: 1,
                isEnabled: true,
                hasPresentedPlayback: true,
                isLoadShedding: false,
                settings: DanmakuSettings(danmakuKit: .init(displayArea: .init(fraction: fraction))),
                topInset: 8,
                bottomInset: 54
            ))
            XCTAssertEqual(view.debugContentFrameHeight, 180, accuracy: 0.5, "内容区高应为 242-8-54")
            XCTAssertEqual(
                view.debugScrollLaneCount, lanes,
                "显示区域 \(Int(fraction * 100))% 应解析出 \(lanes) 条滚动泳道"
            )
        }
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
