import AVFoundation
import OSLog
import UIKit

// MARK: - Timeline lane allocator

/// 时间轴记账式泳道分配。占用控制的是碰撞放置而非容量：全部泳道繁忙时选最早
/// 可复用的一条。滚动泳道在“新弹幕进场点扫过旧弹幕尾端”的时刻即可复用
/// （开始 + 时长 × 位图宽/(画布宽+位图宽)）：短弹幕比固定比例复用得更早，
/// 长弹幕自动延后，两个方向都不产生碰撞；静态泳道占用整个展示时长。
struct DanmakuSyncLaneAllocator {
    private(set) var scrollingFreeAt: [Double]
    private(set) var topFreeAt: [Double]
    private(set) var bottomFreeAt: [Double]
    /// 下一次优先尝试的滚动泳道：轮转铺开，避免弹幕永远挤在最上面几条泳道。
    private var scrollingCursor = 0

    init(laneCount: Int) {
        let resolvedCount = max(1, laneCount)
        scrollingFreeAt = Array(repeating: 0, count: resolvedCount)
        let staticCount = max(resolvedCount / 3, 2)
        topFreeAt = Array(repeating: 0, count: staticCount)
        bottomFreeAt = Array(repeating: 0, count: staticCount)
    }

    /// `reusableAt` = 本次弹幕自己的“尾端被下一发进场点扫过”的绝对时刻。
    /// 从上次分配位置开始轮转找空闲泳道，使弹幕在垂直方向铺满可用区域。
    mutating func reserveScrollingLane(
        at entryTime: Double,
        reusableAt: Double,
        allowsOverlap: Bool
    ) -> Int? {
        let count = scrollingFreeAt.count
        guard count > 0 else { return nil }
        for step in 0..<count {
            let lane = (scrollingCursor + step) % count
            if scrollingFreeAt[lane] <= entryTime {
                scrollingCursor = (lane + 1) % count
                scrollingFreeAt[lane] = reusableAt
                return lane
            }
        }
        guard allowsOverlap else { return nil }
        let lane = Self.earliestFreeLane(in: scrollingFreeAt)
        scrollingCursor = (lane + 1) % count
        scrollingFreeAt[lane] = max(scrollingFreeAt[lane], reusableAt)
        return lane
    }

    mutating func reserveTopLane(
        at startTime: Double,
        duration: Double,
        allowsOverlap: Bool
    ) -> Int? {
        Self.reserveStaticLane(in: &topFreeAt, at: startTime, duration: duration, allowsOverlap: allowsOverlap)
    }

    mutating func reserveBottomLane(
        at startTime: Double,
        duration: Double,
        allowsOverlap: Bool
    ) -> Int? {
        Self.reserveStaticLane(in: &bottomFreeAt, at: startTime, duration: duration, allowsOverlap: allowsOverlap)
    }

    mutating func markScrollingLane(_ lane: Int, reusableAt: Double) {
        guard scrollingFreeAt.indices.contains(lane) else { return }
        scrollingFreeAt[lane] = max(scrollingFreeAt[lane], reusableAt)
    }

    mutating func markTopLane(_ lane: Int, freeAt: Double) {
        guard topFreeAt.indices.contains(lane) else { return }
        topFreeAt[lane] = max(topFreeAt[lane], freeAt)
    }

    mutating func markBottomLane(_ lane: Int, freeAt: Double) {
        guard bottomFreeAt.indices.contains(lane) else { return }
        bottomFreeAt[lane] = max(bottomFreeAt[lane], freeAt)
    }

    private static func earliestFreeLane(in pool: [Double]) -> Int {
        pool.indices.min(by: { pool[$0] < pool[$1] }) ?? 0
    }

    private static func reserveStaticLane(
        in pool: inout [Double],
        at startTime: Double,
        duration: Double,
        allowsOverlap: Bool
    ) -> Int? {
        if let lane = pool.firstIndex(where: { $0 <= startTime }) {
            pool[lane] = startTime + duration
            return lane
        }
        guard allowsOverlap else { return nil }
        let lane = Self.earliestFreeLane(in: pool)
        pool[lane] = max(pool[lane], startTime + duration)
        return lane
    }
}

// MARK: - Bullet layer

/// 位图子弹层：内容是预渲染的 CoreText/表情富文本位图，动画完全交给
/// AVSynchronizedLayer 的媒体时间轴。NSNull actions 阻止隐式动画干扰。
final class DanmakuSyncBulletLayer: CALayer {
    private let contentLayer = CALayer()

    override init() {
        super.init()
        setup()
    }

    override init(layer: Any) {
        // Core Animation 为 presentation() 复制子树时不得重复 setup。
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        let nullActions = [
            "bounds": NSNull(),
            "position": NSNull(),
            "opacity": NSNull(),
            "contents": NSNull(),
            "sublayers": NSNull(),
        ]
        actions = nullActions
        contentLayer.actions = nullActions
        contentLayer.contentsGravity = .resize
        addSublayer(contentLayer)
    }

    func configure(image: CGImage, size: CGSize, contentsScale: CGFloat) {
        bounds = CGRect(origin: .zero, size: size)
        contentLayer.contentsScale = contentsScale
        contentLayer.frame = bounds
        contentLayer.contents = image
        shouldRasterize = false
    }

    var debugContentLayerImage: CGImage? {
        guard let raw = contentLayer.contents,
              CFGetTypeID(raw as CFTypeRef) == CGImage.typeID else {
            return nil
        }
        return unsafeBitCast(raw as CFTypeRef, to: CGImage.self)
    }

    var contentLayerContentsPresent: Bool { contentLayer.contents != nil }

    func prepareForReuse() {
        removeAllAnimations()
        contentLayer.removeAllAnimations()
        contentLayer.contents = nil
        opacity = 1
        removeFromSuperlayer()
    }
}

// MARK: - Text bitmap cache

private nonisolated final class DanmakuSyncCachedText: @unchecked Sendable {
    let image: CGImage
    let size: CGSize
    let missingEmoteURLs: Set<URL>

    init(image: CGImage, size: CGSize, missingEmoteURLs: Set<URL> = []) {
        self.image = image
        self.size = size
        self.missingEmoteURLs = missingEmoteURLs
    }
}

private nonisolated struct DanmakuPrewarmRawJob: Sendable {
    let key: String
    let item: DanmakuItem
    let viewportWidth: CGFloat
    let fontWeight: DanmakuFontWeightOption
    let fontScale: Double
    let scale: CGFloat
    let emotes: [URL: DanmakuEmoteBitmap]
}

// MARK: - Synchronized-layer renderer

/// 挂在 `AVSynchronizedLayer(playerItem:)` 上的弹幕渲染后端：动画的 beginTime
/// 直接使用媒体时间，暂停/seek/倍速由 Core Animation 随媒体时钟自动呈现，
/// 主线程仅做 0.25s 一次的物化/回收排程，不做逐帧绘制。
@MainActor
final class DanmakuSynchronizedLayerView: UIView, DanmakuOverlayRendering {
    private enum DanmakuSyncMode: Equatable {
        case scroll
        case top
        case bottom
    }

    private struct SyncActiveEntry {
        let layer: DanmakuSyncBulletLayer
        let mode: DanmakuSyncMode
        var lane: Int
        let size: CGSize
        let startTime: Double
        let endTime: Double
        let item: DanmakuItem
        var missingEmoteURLs: Set<URL>
    }

    private struct SyncLayoutParameters: Equatable {
        let laneHeight: CGFloat
        let scrollLaneCount: Int
        let staticLaneCount: Int
        let contentFrame: CGRect
        let opacity: CGFloat
    }

    private static let schedulerInterval: Double = 0.25
    private static let schedulingLookAhead: Double = 2
    private static let prewarmLookAhead: Double = 4.5
    private static let maximumPrewarmItemsPerPass = 24
    private static let minimumRollingStartInterval: Double = 0.01
    private static let seekResyncThreshold: Double = 1.25
    private static let backwardSeekResyncThreshold: Double = 0.35
    private static let recycleGrace: Double = 0.2
    /// 排队宽限：弹幕因泳道/容量繁忙而等待超过该时长后放弃。泳道复用最坏
    /// 等待 ≈ 时长 × 0.5（位图与画布等宽的极端弹幕），3.0s 覆盖绝大多数排队。
    private static let lateEntryGrace: Double = 3
    private static let maximumPooledLayers = 256
    private static let baseFontSize: CGFloat = 18
    private static let emoteRetryCooldown: Duration = .seconds(15)

    // MARK: Configuration state

    private var configuration: DanmakuOverlayConfiguration?
    private var layoutParameters: SyncLayoutParameters?
    private var lastAppliedMaxVisibleCount: Int?
    private var viewportWidth: CGFloat { max(bounds.width, 1) }

    // MARK: Timeline state

    private weak var playbackPlayer: AVPlayer?
    private var currentItemObservation: NSKeyValueObservation?
    private var timeObserver: Any?
    private weak var timeObserverPlayer: AVPlayer?
    private var timeJumpObserver: NSObjectProtocol?
    private var prewarmTask: Task<Void, Never>?
    private var activeEmoteLoadTasks: [URL: Task<Void, Never>] = [:]
    private var incompleteCacheKeysByURL: [URL: Set<String>] = [:]
    private var failedEmoteCooldownByURL: [URL: ContinuousClock.Instant] = [:]
    private var synchronizedLayer: AVSynchronizedLayer?
    private var containerLayer: CALayer?
    private var sortedItems: [DanmakuItem] = []
    private var cursor = 0
    private var laneAllocator = DanmakuSyncLaneAllocator(laneCount: 14)
    private var activeEntries: [SyncActiveEntry] = []
    private var layerPool: [DanmakuSyncBulletLayer] = []
    // 已物化且光标仍在其后方的物品 id：防止合并重排后光标回落导致重复物化
    //（重复体占满 maximumActiveCount 配额，新弹幕停止进场）。
    private var materializedAheadIds: Set<String> = []
    private var lastObservedPlaybackTime: Double?
    private var lastRemappedParameters: SyncLayoutParameters?
    private var layoutResynchronizationWork: DispatchWorkItem?
    private var lastLayoutSize: CGSize = .zero
    private var isTransitioning = false
    private(set) var isLoadSheddingValue = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // 挂窗前 install/apply 时 isRenderingActive 为 false（无窗口），进入窗口后
        // 必须重触发，否则排程观察器永远不会添加，弹幕整体不可见。
        updateRenderingActivity()
    }

    var cachedEmoteImageProvider: (URL) -> UIImage? = { BiliEmoteImageStore.shared.cachedImage(for: $0) }
    var loadEmoteImageHandler: (URL) async -> UIImage? = { await BiliEmoteImageStore.shared.image(for: $0) }

    // MARK: Test hooks（@testable 使用）

    var isSyncLayerInstalled: Bool { synchronizedLayer != nil }
    var activeDanmakuCount: Int { activeEntries.count }
    var pooledLayerCount: Int { layerPool.count }
    private(set) var debugSynchronousTextRasterizationCount = 0
    private(set) var debugBackgroundPrewarmRasterizationCount = 0
    /// 游标之后尚未处理的物品数（含排队等待泳道的弹幕）。
    var debugPendingDanmakuCount: Int { max(0, sortedItems.count - cursor) }

    /// 当前布局解析出的滚动泳道数（显示区域占比验证用）。
    var debugScrollLaneCount: Int { layoutParameters?.scrollLaneCount ?? 0 }
    var debugContentFrameHeight: CGFloat { layoutParameters?.contentFrame.height ?? 0 }
    var debugContentFrame: CGRect? { layoutParameters?.contentFrame }

    func debugIsTextCached(for item: DanmakuItem, settings: DanmakuSettings) -> Bool {
        let key = cacheKey(for: item, viewportWidth: max(viewportWidth, 1), settings: settings.normalized)
        return textCache.object(forKey: key as NSString) != nil
    }

    func debugCachedTextHasMissingEmotes(for item: DanmakuItem, settings: DanmakuSettings) -> Bool? {
        let key = cacheKey(for: item, viewportWidth: max(viewportWidth, 1), settings: settings.normalized)
        guard let cached = textCache.object(forKey: key as NSString) else { return nil }
        return !cached.missingEmoteURLs.isEmpty
    }

    func debugActiveBulletContents(for itemID: String) -> CGImage? {
        activeEntries.first(where: { $0.item.id == itemID })?.layer.debugContentLayerImage
    }

    func debugPrewarmForTesting(at now: Double) {
        guard let configuration else { return }
        prewarmUpcomingTextCache(
            after: now,
            through: now + Self.prewarmLookAhead,
            configuration: configuration
        )
    }

    /// 以显式媒体时刻驱动一次排程/回收（单测与诊断用，绕过真实播放器时钟）。
    func debugScheduleForTesting(at now: Double) {
        guard isRenderingActive, synchronizedLayer != nil else { return }
        lastObservedPlaybackTime = now
        recycleExpiredLayers(at: now)
        scheduleItems(through: now + Self.schedulingLookAhead, currentTime: now)
    }

    func debugResynchronizeForTesting(at now: Double) {
        resynchronizePresentation(at: now)
    }

    /// 首颗滚动弹幕动画的 beginTime（媒体时间）：断言迟到弹幕被钳制到右缘进场。
    var debugFirstScrollAnimationBeginTime: Double? {
        for entry in activeEntries {
            if let animation = entry.layer.animation(forKey: "danmaku.sync.scroll") {
                return animation.beginTime
            }
        }
        return nil
    }

    var debugScrollAnimationBeginTimes: [Double] {
        activeEntries.compactMap { entry in
            entry.layer.animation(forKey: "danmaku.sync.scroll")?.beginTime
        }.sorted()
    }

    /// 诊断：同步层/容器/首个活动子弹的 frame、opacity、contents 状态。
    var debugLayerSummary: String {
        let bullet = activeEntries.first?.layer
        let bulletFrame = bullet?.frame ?? .zero
        let bulletOpacity = bullet?.opacity ?? -1
        let hasContents = bullet?.contentLayerContentsPresent ?? false
        let presentationFrame = bullet?.presentation()?.frame ?? .zero
        let animationKeys = (bullet?.animationKeys() ?? []).joined(separator: ",")
        return [
            "syncFrame=\(synchronizedLayer?.frame ?? .zero)",
            "containerFrame=\(containerLayer?.frame ?? .zero)",
            "bounds=\(bounds)",
            "active=\(activeEntries.count)",
            "pending=\(debugPendingDanmakuCount)",
            "bulletFrame=\(bulletFrame)",
            "presentationFrame=\(presentationFrame)",
            "bulletOpacity=\(bulletOpacity)",
            "bulletContents=\(hasContents)",
            "animKeys=\(animationKeys)",
            "playerTime=\(String(format: "%.2f", resolvedPlaybackTime()))",
        ].joined(separator: " ")
    }

    private let textCache = NSCache<NSString, DanmakuSyncCachedText>()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        clipsToBounds = true
        textCache.totalCostLimit = 24 * 1024 * 1024
        textCache.countLimit = 768
    }

    required init?(coder: NSCoder) { nil }

    private var resolvedDisplayScale: CGFloat {
        if let scale = window?.windowScene?.screen.scale, scale > 0 {
            return scale
        }
        let traitScale = traitCollection.displayScale
        return traitScale > 0 ? traitScale : 3
    }

    deinit {
        MainActor.assumeIsolated {
            cancelEmoteLoads()
            currentItemObservation?.invalidate()
            currentItemObservation = nil
            teardownRendering()
        }
    }

    // MARK: DanmakuOverlayRendering

    func apply(configuration: DanmakuOverlayConfiguration) {
        let previousParameters = layoutParameters
        let previousMaxVisibleCount = lastAppliedMaxVisibleCount
        let nextMaxVisibleCount = configuration.settings.danmakuKit.normalizedMaxVisibleCount
        self.configuration = configuration
        self.lastAppliedMaxVisibleCount = nextMaxVisibleCount
        isLoadSheddingValue = configuration.isLoadShedding

        let parameters = resolveLayoutParameters(for: configuration)
        let parametersChanged = parameters != previousParameters
        if parametersChanged {
            layoutParameters = parameters
        }
        applyContainerOpacity(parameters: parameters)

        guard configuration.isEnabled, configuration.hasPresentedPlayback else {
            if parametersChanged {
                rebuildAllocatorIfNeeded(parameters: parameters)
            }
            sortedItems = []
            restartSchedulingAtPlaybackTime()
            updateRenderingActivity()
            return
        }

        // 窗口滑动（每 8s 重算 + 状态变化）走增量合并：飞行中子弹保留，
        // 不清场。全量重放仅限空集合、可见上限收紧与禁用切换；几何/布局参数
        // 变更（如横竖屏旋转、inset 切换）保留在途弹幕并重映射坐标。
        let incoming = configuration.items.sorted { $0.time < $1.time }
        let merged = Self.mergedById(current: sortedItems, incoming: incoming)
        let itemsChanged = merged != sortedItems
        sortedItems = merged

        if sortedItems.isEmpty
            || (previousMaxVisibleCount.map { nextMaxVisibleCount < $0 } ?? false) {
            if parametersChanged {
                rebuildAllocatorIfNeeded(parameters: parameters)
            }
            restartSchedulingAtPlaybackTime()
        } else if parametersChanged {
            relayoutActiveEntriesForGeometryChange()
        } else if let previousMaxVisibleCount,
                  nextMaxVisibleCount > previousMaxVisibleCount,
                  isRenderingActive,
                  synchronizedLayer != nil {
            let now = resolvedPlaybackTime()
            positionCursor(at: now)
            scheduleItems(through: now + Self.schedulingLookAhead, currentTime: now)
        } else if itemsChanged {
            let now = resolvedPlaybackTime()
            positionCursor(at: now)
            if isRenderingActive {
                prewarmUpcomingTextCache(
                    after: now + Self.schedulingLookAhead,
                    through: now + Self.prewarmLookAhead,
                    configuration: configuration
                )
            }
        } else if synchronizedLayer == nil {
            updateRenderingActivity()
        }
        updateRenderingActivity()
    }

    /// 按 id 去重的增量合并（当前集合保留，新窗口物品并入），保持时间序。
    nonisolated static func mergedById(
        current: [DanmakuItem],
        incoming: [DanmakuItem]
    ) -> [DanmakuItem] {
        var seen = Set<String>()
        var merged: [DanmakuItem] = []
        merged.reserveCapacity(current.count + incoming.count)
        for item in current where seen.insert(item.id).inserted {
            merged.append(item)
        }
        for item in incoming where seen.insert(item.id).inserted {
            merged.append(item)
        }
        return merged.sorted { $0.time < $1.time }
    }

    func synchronizePlaybackTime(_ time: TimeInterval, force: Bool) {
        guard synchronizedLayer != nil else { return }
        let mediaTime = resolvedPlaybackTime()
        guard force || abs(mediaTime - time) > Self.seekResyncThreshold else { return }
        resynchronizePresentation(at: mediaTime)
    }

    func setLayoutTransitioning(_ transitioning: Bool) {
        guard isTransitioning != transitioning else { return }
        isTransitioning = transitioning
        if !transitioning {
            layoutResynchronizationWork?.cancel()
            layoutResynchronizationWork = nil
            relayoutActiveEntriesForGeometryChange()
        }
    }

    func stop() {
        cancelEmoteLoads()
        incompleteCacheKeysByURL.removeAll()
        failedEmoteCooldownByURL.removeAll()
        teardownRendering()
    }

    func attachPlaybackPlayer(_ player: AVPlayer?) {
        guard playbackPlayer !== player else { return }
        teardownRendering()
        currentItemObservation?.invalidate()
        currentItemObservation = nil
        playbackPlayer = player
        updateRenderingActivity()
        guard let player else { return }
        currentItemObservation = player.observe(\.currentItem, options: [.initial, .new]) { [weak self] observedPlayer, _ in
            Task { @MainActor [weak self] in
                guard let self, self.playbackPlayer === observedPlayer else { return }
                self.installSynchronizedLayerIfNeeded(for: observedPlayer.currentItem)
            }
        }
    }

    // MARK: Rendering activity

    private var isRenderingActive: Bool {
        guard let configuration,
              configuration.isEnabled,
              configuration.hasPresentedPlayback,
              window != nil,
              playbackPlayer != nil
        else { return false }
        return true
    }

    private func updateRenderingActivity() {
        guard isRenderingActive, let player = playbackPlayer else {
            teardownRendering()
            return
        }
        installSynchronizedLayerIfNeeded(for: player.currentItem)
        guard synchronizedLayer != nil else { return }
        if timeObserver == nil {
            addScheduler(to: player)
        }
    }

    private func teardownRendering() {
        prewarmTask?.cancel()
        prewarmTask = nil
        teardownSynchronizedLayer()
        removeTimeObserverIfNeeded()
        layoutResynchronizationWork?.cancel()
        layoutResynchronizationWork = nil
        lastObservedPlaybackTime = nil
    }

    // MARK: Synchronized layer lifecycle

    private func installSynchronizedLayerIfNeeded(for item: AVPlayerItem?) {
        if let synchronizedLayer, synchronizedLayer.playerItem === item { return }
        teardownSynchronizedLayer()
        guard let item else { return }

        let nullActions: [String: CAAction] = [
            "position": NSNull(),
            "bounds": NSNull(),
            "frame": NSNull(),
            "opacity": NSNull(),
            "sublayers": NSNull(),
            "masksToBounds": NSNull(),
        ]
        let syncLayer = AVSynchronizedLayer(playerItem: item)
        syncLayer.actions = nullActions
        syncLayer.frame = bounds
        syncLayer.masksToBounds = true
        let container = CALayer()
        container.frame = bounds
        container.actions = nullActions
        syncLayer.addSublayer(container)
        layer.addSublayer(syncLayer)
        synchronizedLayer = syncLayer
        containerLayer = container
        PlayerMetricsLog.logger.info("danmakuSync installed")

        timeJumpObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemTimeJumped,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleTimeJumpNotification()
            }
        }
        restartSchedulingAtPlaybackTime()
    }

    private func handleTimeJumpNotification() {
        guard isRenderingActive, synchronizedLayer != nil else { return }
        let now = resolvedPlaybackTime()
        if let lastObservedPlaybackTime,
           !hasDiscontinuousTimeJump(from: lastObservedPlaybackTime, to: now) {
            // AVPlayer 在暂停/恢复播放及倍速切换时也会发出 AVPlayerItemTimeJumped；
            // 若媒体时间未真正跳变，直接交给 AVSynchronizedLayer 顺延继续，避免清屏重排。
            return
        }
        resynchronizePresentation(at: now)
    }

    private func hasDiscontinuousTimeJump(from previous: Double, to current: Double) -> Bool {
        current + Self.backwardSeekResyncThreshold < previous
            || current - previous > Self.seekResyncThreshold
    }

    private func teardownSynchronizedLayer() {
        recycleAllActiveLayers()
        timeJumpObserver.map { NotificationCenter.default.removeObserver($0) }
        timeJumpObserver = nil
        synchronizedLayer?.removeFromSuperlayer()
        synchronizedLayer = nil
        containerLayer = nil
    }

    // MARK: Scheduling

    private func removeTimeObserverIfNeeded() {
        if let timeObserver, let observerPlayer = timeObserverPlayer {
            observerPlayer.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        timeObserverPlayer = nil
    }

    private func addScheduler(to player: AVPlayer) {
        removeTimeObserverIfNeeded()
        timeObserverPlayer = player
        let interval = CMTime(seconds: Self.schedulerInterval, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let seconds = time.seconds.isFinite ? max(0, time.seconds) : 0
            Task { @MainActor [weak self] in
                self?.handleSchedulerTick(at: seconds)
            }
        }
    }

    private func handleSchedulerTick(at now: Double) {
        guard isRenderingActive, synchronizedLayer != nil else { return }
        if let lastObservedPlaybackTime,
           hasDiscontinuousTimeJump(from: lastObservedPlaybackTime, to: now) {
            resynchronizePresentation(at: now)
            return
        }
        lastObservedPlaybackTime = now
        recycleExpiredLayers(at: now)
        scheduleItems(through: now + Self.schedulingLookAhead, currentTime: now)
    }

    private func restartSchedulingAtPlaybackTime() {
        guard isRenderingActive, synchronizedLayer != nil else { return }
        let now = resolvedPlaybackTime()
        lastObservedPlaybackTime = now
        recycleAllActiveLayers()
        materializedAheadIds.removeAll()
        positionCursor(at: now)
        scheduleItems(through: now + Self.schedulingLookAhead, currentTime: now)
    }

    private func resynchronizePresentation(at explicitTime: Double? = nil) {
        guard synchronizedLayer != nil, bounds.width > 0, bounds.height > 0 else { return }
        let now = explicitTime ?? resolvedPlaybackTime()
        // 时间轴跳变（seek/循环）= 全量回收 + 重放，已物化记录一并清空，
        // 否则重放窗口内的物品全部被去重集合挡住，弹幕从此消失。
        materializedAheadIds.removeAll()
        lastObservedPlaybackTime = now
        recycleAllActiveLayers()
        positionCursor(at: now)
        scheduleItems(through: now + Self.schedulingLookAhead, currentTime: now)
    }

    private func positionCursor(at now: Double) {
        cursor = lowerBound(of: now - Self.schedulingLookAhead)
    }

    private func scheduleItems(through horizon: Double, currentTime: Double) {
        guard let configuration else { return }
        let parameters = layoutParameters ?? resolveLayoutParameters(for: configuration)
        let maximumActiveCount = DanmakuRenderPolicy.maximumActiveCount(
            width: viewportWidth,
            settings: configuration.settings,
            rate: configuration.playbackRate,
            loadShedding: configuration.isLoadShedding
        )
        // 从游标向后扫描到 horizon。队头被泳道/容量阻塞时保留游标下一拍重试，
        // 后续弹幕仍可占用当前空闲的泳道（与 B 站逐泳道取弹幕一致，避免一条
        // 长弹幕堵住整条队列造成进场断流）；已放置/放弃的物品由去重集合记账。
        var firstBusyIndex: Int?
        var index = cursor
        while index < sortedItems.count, sortedItems[index].time <= horizon {
            let item = sortedItems[index]
            switch scheduleItem(
                item,
                parameters: parameters,
                configuration: configuration,
                currentTime: currentTime,
                horizon: horizon,
                maximumActiveCount: maximumActiveCount
            ) {
            case .placed, .skipped:
                index += 1
            case .busy:
                if firstBusyIndex == nil { firstBusyIndex = index }
                index += 1
            }
        }
        cursor = firstBusyIndex ?? min(index, sortedItems.count)
        prewarmUpcomingTextCache(
            after: horizon,
            through: currentTime + Self.prewarmLookAhead,
            configuration: configuration
        )
    }

    private enum ItemSchedulingOutcome {
        case placed
        case skipped
        case busy
    }

    private func scheduleItem(
        _ item: DanmakuItem,
        parameters: SyncLayoutParameters,
        configuration: DanmakuOverlayConfiguration,
        currentTime: Double,
        horizon: Double,
        maximumActiveCount: Int
    ) -> ItemSchedulingOutcome {
        // 游标会因窗口重发而回退重扫：已物化的物品必须跳过，否则同一句
        // 弹幕会被重复放置并叠在原弹幕上（Build 165 背压改造遗漏的判重）。
        guard !materializedAheadIds.contains(item.id) else { return .skipped }
        guard activeEntries.count < maximumActiveCount else { return .busy }
        guard DanmakuRenderPolicy.supports(item, settings: configuration.settings) else {
            materializedAheadIds.insert(item.id)
            return .skipped
        }
        let plannedStart = max(0, item.time)
        // 重放回看窗口或排队迟到的弹幕：宽限内从右缘立即进场（钳制开始时刻），
        // 超过宽限直接放弃；绝不按过去的 beginTime 从屏幕中间冒出。
        guard plannedStart >= currentTime - Self.lateEntryGrace else {
            materializedAheadIds.insert(item.id)
            return .skipped
        }
        let mode: DanmakuSyncMode
        let requestedStart = max(plannedStart, currentTime)
        var effectiveStart = requestedStart
        let cached = cachedText(for: item, configuration: configuration)
        // 滚动弹幕按固定速度（pt/秒）计算时长：竖屏画布窄、时长自然更短，
        // 与横屏观感速度一致，泳道周转也更快。静态弹幕仍用固定展示时长。
        let duration: Double
        if item.isTopAnchored {
            mode = .top
            duration = DanmakuRenderPolicy.duration(for: item, viewportWidth: viewportWidth)
        } else if item.isBottomAnchored {
            mode = .bottom
            duration = DanmakuRenderPolicy.duration(for: item, viewportWidth: viewportWidth)
        } else {
            mode = .scroll
            duration = DanmakuRenderPolicy.scrollDuration(
                viewportWidth: viewportWidth,
                bitmapWidth: cached.size.width
            )
            guard let spacedStart = rollingStartTime(
                afterSpacingFromActiveStarts: requestedStart,
                horizon: horizon,
                latestAllowedStart: plannedStart + Self.lateEntryGrace
            ) else { return .busy }
            effectiveStart = spacedStart
        }
        let allowsOverlap = configuration.settings.danmakuKit.allowsDanmakuOverlap
        let lane: Int?
        switch mode {
        case .scroll:
            let bitmapWidth = max(cached.size.width, 1)
            let canvasWidth = max(viewportWidth, 1)
            // 新弹幕进场点（画布右缘）扫过旧弹幕尾端后才复用该泳道。
            let reusableAt = effectiveStart
                + duration * Double(bitmapWidth / (canvasWidth + bitmapWidth))
            lane = laneAllocator.reserveScrollingLane(
                at: effectiveStart, reusableAt: reusableAt, allowsOverlap: allowsOverlap
            )
        case .top:
            lane = laneAllocator.reserveTopLane(
                at: effectiveStart, duration: duration, allowsOverlap: allowsOverlap
            )
        case .bottom:
            lane = laneAllocator.reserveBottomLane(
                at: effectiveStart, duration: duration, allowsOverlap: allowsOverlap
            )
        }
        guard let lane else { return .busy }
        materialize(
            item,
            cached: cached,
            mode: mode,
            lane: lane,
            parameters: parameters,
            configuration: configuration,
            effectiveStart: effectiveStart,
            duration: duration
        )
        materializedAheadIds.insert(item.id)
        return .placed
    }

    private func materialize(
        _ item: DanmakuItem,
        cached: DanmakuSyncCachedText,
        mode: DanmakuSyncMode,
        lane: Int,
        parameters: SyncLayoutParameters,
        configuration: DanmakuOverlayConfiguration,
        effectiveStart: Double,
        duration: Double
    ) {
        guard let containerLayer else { return }
        let endTime = effectiveStart + duration
        let bulletLayer = dequeueLayer()
        bulletLayer.configure(
            image: cached.image,
            size: cached.size,
            contentsScale: resolvedDisplayScale
        )
        containerLayer.addSublayer(bulletLayer)
        configureAnimations(
            on: bulletLayer,
            bulletSize: cached.size,
            mode: mode,
            lane: lane,
            parameters: parameters,
            configuration: configuration,
            startTime: effectiveStart,
            duration: duration
        )
        activeEntries.append(SyncActiveEntry(
            layer: bulletLayer,
            mode: mode,
            lane: lane,
            size: cached.size,
            startTime: effectiveStart,
            endTime: endTime,
            item: item,
            missingEmoteURLs: cached.missingEmoteURLs
        ))
    }

    /// Stagger only starts that would bunch against already admitted rolling comments.
    /// The active list is bounded by the existing load cap, and old starts disappear as
    /// their layers recycle, so this adds no separate queue or timeline state.
    private func rollingStartTime(
        afterSpacingFromActiveStarts requestedStart: Double,
        horizon: Double,
        latestAllowedStart: Double
    ) -> Double? {
        let existingStarts = activeEntries.compactMap { entry -> Double? in
            guard entry.mode == .scroll else { return nil }
            return entry.startTime
        }.sorted()

        var candidate = requestedStart
        let spacingTolerance = 0.000_001
        for existingStart in existingStarts {
            if candidate >= existingStart + Self.minimumRollingStartInterval - spacingTolerance {
                continue
            }
            if candidate <= existingStart - Self.minimumRollingStartInterval + spacingTolerance {
                break
            }
            candidate = existingStart + Self.minimumRollingStartInterval
        }
        guard candidate <= horizon, candidate <= latestAllowedStart else { return nil }
        return candidate
    }

    // MARK: Animation construction

    private func configureAnimations(
        on layer: DanmakuSyncBulletLayer,
        bulletSize: CGSize,
        mode: DanmakuSyncMode,
        lane: Int,
        parameters: SyncLayoutParameters,
        configuration: DanmakuOverlayConfiguration,
        startTime: Double,
        duration: Double
    ) {
        let contentFrame = parameters.contentFrame
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let laneHeight = parameters.laneHeight
        switch mode {
        case .scroll:
            let y = contentFrame.minY + laneHeight * (CGFloat(lane) + 0.5)
            let startX = contentFrame.maxX + bulletSize.width / 2
            let endX = contentFrame.minX - bulletSize.width / 2
            layer.position = CGPoint(x: endX, y: y)
            layer.opacity = 1
            let movement = CABasicAnimation(keyPath: "position.x")
            movement.fromValue = startX
            movement.toValue = endX
            configureAnimation(
                movement,
                beginTime: startTime,
                duration: duration,
                timingFunction: CAMediaTimingFunction(name: .linear),
                configuration: configuration
            )
            layer.add(movement, forKey: "danmaku.sync.scroll")

        case .top, .bottom:
            let y: CGFloat
            if mode == .top {
                y = contentFrame.minY + laneHeight * (CGFloat(lane) + 0.5)
            } else {
                y = contentFrame.maxY - laneHeight * (CGFloat(lane) + 0.5)
            }
            layer.position = CGPoint(x: contentFrame.midX, y: y)
            layer.opacity = 0
            let visibility = CAKeyframeAnimation(keyPath: "opacity")
            visibility.values = [0, 1, 1, 0]
            visibility.keyTimes = [0, 0.001, 0.999, 1]
            visibility.calculationMode = .linear
            configureAnimation(
                visibility,
                beginTime: startTime,
                duration: duration,
                timingFunction: nil,
                configuration: configuration
            )
            layer.add(visibility, forKey: "danmaku.sync.visibility")
        }
        CATransaction.commit()
    }

    private func remapAnimations(
        on layer: DanmakuSyncBulletLayer,
        bulletSize: CGSize,
        mode: DanmakuSyncMode,
        lane: Int,
        parameters: SyncLayoutParameters,
        configuration: DanmakuOverlayConfiguration,
        startTime: Double,
        duration: Double
    ) {
        let contentFrame = parameters.contentFrame
        let laneHeight = parameters.laneHeight
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        switch mode {
        case .scroll:
            let y = contentFrame.minY + laneHeight * (CGFloat(lane) + 0.5)
            let startX = contentFrame.maxX + bulletSize.width / 2
            let endX = contentFrame.minX - bulletSize.width / 2
            layer.position = CGPoint(x: endX, y: y)
            let existing = layer.animation(forKey: "danmaku.sync.scroll") as? CABasicAnimation
            let existingFrom = (existing?.fromValue as? NSNumber)?.doubleValue
            let existingTo = (existing?.toValue as? NSNumber)?.doubleValue
            let matchesTrack = existingFrom.map { abs($0 - Double(startX)) <= 0.5 } ?? false
                && existingTo.map { abs($0 - Double(endX)) <= 0.5 } ?? false
            if !matchesTrack {
                let movement = CABasicAnimation(keyPath: "position.x")
                movement.fromValue = startX
                movement.toValue = endX
                configureAnimation(
                    movement,
                    beginTime: startTime,
                    duration: duration,
                    timingFunction: CAMediaTimingFunction(name: .linear),
                    configuration: configuration
                )
                layer.add(movement, forKey: "danmaku.sync.scroll")
            }

        case .top, .bottom:
            let y: CGFloat
            if mode == .top {
                y = contentFrame.minY + laneHeight * (CGFloat(lane) + 0.5)
            } else {
                y = contentFrame.maxY - laneHeight * (CGFloat(lane) + 0.5)
            }
            layer.position = CGPoint(x: contentFrame.midX, y: y)
        }
        CATransaction.commit()
    }

    private func configureAnimation(
        _ animation: CAAnimation,
        beginTime: Double,
        duration: Double,
        timingFunction: CAMediaTimingFunction?,
        configuration: DanmakuOverlayConfiguration
    ) {
        animation.beginTime = beginTime > 0 ? beginTime : AVCoreAnimationBeginTimeAtZero
        animation.duration = max(0.001, duration)
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
        animation.timingFunction = timingFunction
        let frameRate = MetalDanmakuFrameRatePolicy.preferredFramesPerSecond(
            displayMaximum: window?.windowScene?.screen.maximumFramesPerSecond ?? 60,
            isLoadShedding: configuration.isLoadShedding,
            isLowPowerMode: PlaybackEnvironment.current.isLowPowerModeEnabled,
            isThermallyConstrained: PlaybackEnvironment.current.isThermallyConstrained
        )
        let frameRateValue = Float(frameRate)
        animation.preferredFrameRateRange = CAFrameRateRange(
            minimum: min(frameRateValue, 30),
            maximum: frameRateValue,
            preferred: frameRateValue
        )
    }

    // MARK: Recycling

    private func recycleExpiredLayers(at now: Double) {
        guard !activeEntries.isEmpty else { return }
        var writeIndex = 0
        for readIndex in activeEntries.indices {
            let entry = activeEntries[readIndex]
            if entry.endTime + Self.recycleGrace <= now {
                recycleLayer(entry.layer)
            } else {
                if writeIndex != readIndex {
                    activeEntries[writeIndex] = entry
                }
                writeIndex += 1
            }
        }
        if writeIndex < activeEntries.count {
            activeEntries.removeSubrange(writeIndex...)
        }
    }

    private func recycleAllActiveLayers() {
        for entry in activeEntries {
            recycleLayer(entry.layer)
        }
        activeEntries.removeAll()
        lastRemappedParameters = nil
        // 全量回收后泳道占用账本必须清零：若保留 freeAt，已回收子弹会以幽灵
        // 占位挡住重物化（resync 后画面清空），参数变化重建分配器则会放新弹幕
        // 叠上仍在飞的旧弹幕。重放按时间序确定性还原泳道。
        laneAllocator = DanmakuSyncLaneAllocator(
            laneCount: max(1, layoutParameters?.scrollLaneCount ?? 14)
        )
    }

    private func recycleLayer(_ layer: DanmakuSyncBulletLayer) {
        layer.prepareForReuse()
        if layerPool.count < Self.maximumPooledLayers {
            layerPool.append(layer)
        }
    }

    private func dequeueLayer() -> DanmakuSyncBulletLayer {
        if let pooled = layerPool.popLast() {
            return pooled
        }
        return DanmakuSyncBulletLayer()
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        UIView.performWithoutAnimation {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            synchronizedLayer?.frame = bounds
            containerLayer?.frame = bounds
            CATransaction.commit()
            guard bounds.width > 0, bounds.height > 0 else { return }
            guard abs(lastLayoutSize.width - bounds.width) > 0.5
                    || abs(lastLayoutSize.height - bounds.height) > 0.5 else {
                return
            }
            lastLayoutSize = bounds.size
            layoutParameters = configuration.map { resolveLayoutParameters(for: $0) }
            layoutResynchronizationWork?.cancel()
            layoutResynchronizationWork = nil
            relayoutActiveEntriesForGeometryChange()
        }
    }

    private func relayoutActiveEntriesForGeometryChange(at explicitTime: Double? = nil) {
        guard isRenderingActive, synchronizedLayer != nil,
              bounds.width > 0, bounds.height > 0,
              let configuration else {
            if let parameters = layoutParameters {
                rebuildAllocatorIfNeeded(parameters: parameters)
            }
            return
        }
        let parameters = resolveLayoutParameters(for: configuration)
        layoutParameters = parameters
        if lastRemappedParameters == parameters {
            return
        }
        let now = explicitTime ?? resolvedPlaybackTime()
        lastObservedPlaybackTime = now
        recycleExpiredLayers(at: now)

        if activeEntries.isEmpty {
            rebuildAllocatorIfNeeded(parameters: parameters)
            lastRemappedParameters = parameters
        } else if lastRemappedParameters != parameters {
            var nextAllocator = DanmakuSyncLaneAllocator(
                laneCount: max(1, parameters.scrollLaneCount)
            )
            let canvasWidth = max(viewportWidth, 1)
            for index in activeEntries.indices {
                let entry = activeEntries[index]
                let duration = max(0.001, entry.endTime - entry.startTime)
                let laneCount = entry.mode == .scroll
                    ? max(1, parameters.scrollLaneCount)
                    : max(1, parameters.staticLaneCount)
                let remappedLane = entry.lane < laneCount ? entry.lane : (entry.lane % laneCount)
                activeEntries[index].lane = remappedLane
                remapAnimations(
                    on: entry.layer,
                    bulletSize: entry.size,
                    mode: entry.mode,
                    lane: remappedLane,
                    parameters: parameters,
                    configuration: configuration,
                    startTime: entry.startTime,
                    duration: duration
                )
                switch entry.mode {
                case .scroll:
                    let bitmapWidth = max(entry.size.width, 1)
                    let reusableAt = entry.startTime
                        + duration * Double(bitmapWidth / (canvasWidth + bitmapWidth))
                    nextAllocator.markScrollingLane(remappedLane, reusableAt: reusableAt)
                case .top:
                    nextAllocator.markTopLane(remappedLane, freeAt: entry.endTime)
                case .bottom:
                    nextAllocator.markBottomLane(remappedLane, freeAt: entry.endTime)
                }
            }
            laneAllocator = nextAllocator
            lastRemappedParameters = parameters
        }

        positionCursor(at: now)
        scheduleItems(through: now + Self.schedulingLookAhead, currentTime: now)
    }

    // MARK: Layout parameters

    private func resolveLayoutParameters(for configuration: DanmakuOverlayConfiguration) -> SyncLayoutParameters {
        let settings = configuration.settings.normalized
        let contentFrame = DanmakuVideoViewport.insetContentFrame(
            in: bounds,
            aspectRatio: configuration.videoAspectRatio,
            topInset: configuration.topInset,
            bottomInset: configuration.bottomInset,
            settings: settings.danmakuKit
        )
        let font = DanmakuRenderPolicy.font(
            for: DanmakuItem(
                id: "probe", time: 0, mode: 1, fontSize: 25,
                color: 0xFFFFFF, text: "0"
            ),
            viewportWidth: max(viewportWidth, 1),
            scale: settings.danmakuKit.fontScale,
            weight: .regular
        )
        let laneHeight = max(CGFloat(settings.danmakuKit.trackHeight), font.lineHeight + 8)
        let scrollRegionHeight = contentFrame.height * CGFloat(settings.danmakuKit.displayArea.fraction)
        let scrollLaneCount = max(1, Int(scrollRegionHeight / laneHeight))
        let staticLaneCount = max(2, scrollLaneCount / 3)
        let opacity = CGFloat(min(max(settings.danmakuKit.opacity, 0.25), 1))
        return SyncLayoutParameters(
            laneHeight: laneHeight,
            scrollLaneCount: scrollLaneCount,
            staticLaneCount: staticLaneCount,
            contentFrame: contentFrame,
            opacity: opacity
        )
    }

    private func rebuildAllocatorIfNeeded(parameters: SyncLayoutParameters) {
        laneAllocator = DanmakuSyncLaneAllocator(laneCount: max(1, parameters.scrollLaneCount))
    }

    private func applyContainerOpacity(parameters: SyncLayoutParameters) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        containerLayer?.opacity = Float(parameters.opacity)
        CATransaction.commit()
    }

    // MARK: Time

    private func resolvedPlaybackTime() -> Double {
        guard let seconds = playbackPlayer?.currentTime().seconds, seconds.isFinite else { return 0 }
        return max(0, seconds)
    }

    private func lowerBound(of time: Double) -> Int {
        var lower = 0
        var upper = sortedItems.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if sortedItems[middle].time < time {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    // MARK: Text bitmaps

    private func cacheKey(
        for item: DanmakuItem,
        viewportWidth: CGFloat,
        settings: DanmakuSettings
    ) -> String {
        let widthBucket = viewportWidth > 640 ? 1 : 0
        var base = "\(item.text)|\(item.color)|\(Int(item.fontSize))|\(item.mode)|\(widthBucket)|\(settings.danmakuKit.fontWeight)|\(settings.danmakuKit.fontScale)"
        if item.colorful != 0 {
            base += "|c\(item.colorful)"
        }
        if !item.inlineEmotes.isEmpty {
            let emoteDigest = item.inlineEmotes
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value.url)" }
                .joined(separator: ",")
            base += "|\(emoteDigest)"
        }
        return base
    }

    private func referencedEmoteURLs(for item: DanmakuItem) -> [URL] {
        guard !item.inlineEmotes.isEmpty else { return [] }
        var urls: [URL] = []
        var seen = Set<URL>()
        for (token, emote) in item.inlineEmotes {
            guard !token.isEmpty,
                  item.text.contains(token),
                  let urlString = emote.displayURL,
                  let url = URL(string: urlString),
                  seen.insert(url).inserted
            else { continue }
            urls.append(url)
        }
        return urls
    }

    private func emoteSnapshots(for urls: [URL]) -> (snapshots: [URL: DanmakuEmoteBitmap], missingURLs: [URL]) {
        var snapshots: [URL: DanmakuEmoteBitmap] = [:]
        var missingURLs: [URL] = []
        for url in urls {
            if let image = cachedEmoteImageProvider(url),
               let cgImage = image.cgImage {
                snapshots[url] = DanmakuEmoteBitmap(cgImage: cgImage, scale: image.scale)
            } else {
                missingURLs.append(url)
            }
        }
        return (snapshots, missingURLs)
    }

    private func cachedText(
        for item: DanmakuItem,
        configuration: DanmakuOverlayConfiguration
    ) -> DanmakuSyncCachedText {
        let settings = configuration.settings.normalized
        let width = max(viewportWidth, 1)
        let key = cacheKey(for: item, viewportWidth: width, settings: settings)
        let nsKey = key as NSString

        if let cached = textCache.object(forKey: nsKey) {
            if cached.missingEmoteURLs.isEmpty {
                return cached
            }
            let anyNewlyAvailable = cached.missingEmoteURLs.contains { cachedEmoteImageProvider($0) != nil }
            if !anyNewlyAvailable {
                requestEmoteImages(Array(cached.missingEmoteURLs))
                return cached
            }
            textCache.removeObject(forKey: nsKey)
        }

        debugSynchronousTextRasterizationCount += 1
        let emoteURLs = referencedEmoteURLs(for: item)
        let snapshots = emoteSnapshots(for: emoteURLs).snapshots
        let built = Self.buildTextGlyph(
            item: item,
            viewportWidth: width,
            fontWeight: settings.danmakuKit.fontWeight,
            fontScale: settings.danmakuKit.fontScale,
            scale: resolvedDisplayScale,
            cachedEmotes: snapshots,
            placeholderProvider: { BiliEmoteImageStore.shared.placeholderImage(size: $0) }
        )
        let result = built.cached
        textCache.setObject(result, forKey: nsKey, cost: result.image.bytesPerRow * result.image.height)
        if !built.missingImageURLs.isEmpty {
            for url in built.missingImageURLs {
                incompleteCacheKeysByURL[url, default: []].insert(key)
            }
            requestEmoteImages(built.missingImageURLs)
        }
        return result
    }

    private func prewarmUpcomingTextCache(
        after startHorizon: Double,
        through endHorizon: Double,
        configuration: DanmakuOverlayConfiguration
    ) {
        guard endHorizon > startHorizon, !sortedItems.isEmpty else { return }
        let settings = configuration.settings.normalized
        let width = max(viewportWidth, 1)
        let scale = resolvedDisplayScale
        let nowClock = ContinuousClock.now
        var index = lowerBound(of: startHorizon)
        var jobs: [DanmakuPrewarmRawJob] = []
        var emoteURLsToPrefetch: [URL] = []
        var seenPrefetchURLs = Set<URL>()
        var seenKeys = Set<String>()

        while index < sortedItems.count,
              sortedItems[index].time <= endHorizon,
              jobs.count < Self.maximumPrewarmItemsPerPass {
            let item = sortedItems[index]
            index += 1
            guard DanmakuRenderPolicy.supports(item, settings: settings) else { continue }
            let key = cacheKey(for: item, viewportWidth: width, settings: settings)
            guard seenKeys.insert(key).inserted else { continue }
            guard textCache.object(forKey: key as NSString) == nil else { continue }

            let emoteURLs = referencedEmoteURLs(for: item)
            let lookup = emoteSnapshots(for: emoteURLs)
            if !lookup.missingURLs.isEmpty {
                var shouldDeferPlaceholderPrewarm = false
                for url in lookup.missingURLs {
                    let isCoolingDown = failedEmoteCooldownByURL[url].map { $0 > nowClock } ?? false
                    if !isCoolingDown {
                        shouldDeferPlaceholderPrewarm = true
                        if seenPrefetchURLs.insert(url).inserted {
                            emoteURLsToPrefetch.append(url)
                        }
                    }
                }
                if shouldDeferPlaceholderPrewarm {
                    continue
                }
            }

            jobs.append(DanmakuPrewarmRawJob(
                key: key,
                item: item,
                viewportWidth: width,
                fontWeight: settings.danmakuKit.fontWeight,
                fontScale: settings.danmakuKit.fontScale,
                scale: scale,
                emotes: lookup.snapshots
            ))
        }

        if !emoteURLsToPrefetch.isEmpty {
            requestEmoteImages(emoteURLsToPrefetch)
        }
        guard !jobs.isEmpty else { return }
        prewarmTask?.cancel()
        let cache = textCache
        prewarmTask = Task.detached(priority: .utility) { [weak self] in
            var rasterizedCount = 0
            for job in jobs {
                if Task.isCancelled { return }
                let nsKey = job.key as NSString
                if cache.object(forKey: nsKey) != nil { continue }
                let built = Self.buildTextGlyph(
                    item: job.item,
                    viewportWidth: job.viewportWidth,
                    fontWeight: job.fontWeight,
                    fontScale: job.fontScale,
                    scale: job.scale,
                    cachedEmotes: job.emotes
                )
                cache.setObject(
                    built.cached,
                    forKey: nsKey,
                    cost: built.cached.image.bytesPerRow * built.cached.image.height
                )
                rasterizedCount += 1
            }
            if rasterizedCount > 0, !Task.isCancelled {
                await MainActor.run { [weak self] in
                    self?.debugBackgroundPrewarmRasterizationCount += rasterizedCount
                }
            }
        }
    }

    private func requestEmoteImages(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let now = ContinuousClock.now
        for url in urls {
            guard activeEmoteLoadTasks[url] == nil else { continue }
            if let retryAfter = failedEmoteCooldownByURL[url], retryAfter > now {
                continue
            }
            if cachedEmoteImageProvider(url) != nil {
                continue
            }
            let loader = loadEmoteImageHandler
            activeEmoteLoadTasks[url] = Task { [weak self] in
                let loaded = await loader(url)
                await MainActor.run { [weak self] in
                    self?.handleEmoteImageLoaded(for: url, image: loaded)
                }
            }
        }
    }

    private func handleEmoteImageLoaded(for url: URL, image: UIImage?) {
        activeEmoteLoadTasks[url] = nil
        let dependentKeys = incompleteCacheKeysByURL.removeValue(forKey: url) ?? []
        guard image != nil else {
            failedEmoteCooldownByURL[url] = ContinuousClock.now + Self.emoteRetryCooldown
            return
        }
        failedEmoteCooldownByURL.removeValue(forKey: url)

        for key in dependentKeys {
            textCache.removeObject(forKey: key as NSString)
        }

        if let configuration, !activeEntries.isEmpty {
            var didBeginTransaction = false
            for index in activeEntries.indices {
                guard activeEntries[index].missingEmoteURLs.contains(url) else { continue }
                let updated = cachedText(for: activeEntries[index].item, configuration: configuration)
                activeEntries[index].missingEmoteURLs = updated.missingEmoteURLs
                if !didBeginTransaction {
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    didBeginTransaction = true
                }
                activeEntries[index].layer.configure(
                    image: updated.image,
                    size: updated.size,
                    contentsScale: resolvedDisplayScale
                )
            }
            if didBeginTransaction {
                CATransaction.commit()
            }
        }

        if isRenderingActive, let configuration {
            let now = lastObservedPlaybackTime ?? resolvedPlaybackTime()
            prewarmUpcomingTextCache(
                after: now,
                through: now + Self.prewarmLookAhead,
                configuration: configuration
            )
        }
    }

    private func cancelEmoteLoads() {
        for task in activeEmoteLoadTasks.values {
            task.cancel()
        }
        activeEmoteLoadTasks.removeAll()
    }

    private nonisolated static func buildTextGlyph(
        item: DanmakuItem,
        viewportWidth: CGFloat,
        fontWeight: DanmakuFontWeightOption,
        fontScale: Double,
        scale: CGFloat,
        cachedEmotes: [URL: DanmakuEmoteBitmap],
        placeholderProvider: ((CGFloat) -> UIImage)? = nil
    ) -> (cached: DanmakuSyncCachedText, missingImageURLs: [URL]) {
        let resolvedWidth = max(viewportWidth, 1)
        let font = DanmakuRenderPolicy.font(
            for: item,
            viewportWidth: resolvedWidth,
            scale: fontScale,
            weight: fontWeight
        )
        let color = UIColor(
            red: CGFloat((item.color >> 16) & 0xFF) / 255,
            green: CGFloat((item.color >> 8) & 0xFF) / 255,
            blue: CGFloat(item.color & 0xFF) / 255,
            alpha: 1
        )
        let textShadow = NSShadow()
        textShadow.shadowColor = UIColor.black.withAlphaComponent(0.86)
        textShadow.shadowOffset = CGSize(width: 0, height: 1)
        textShadow.shadowBlurRadius = 1.4
        let rendered = DanmakuEmoteAttributedTextRenderer.render(
            item.text,
            emotes: item.inlineEmotes,
            font: font,
            color: color,
            shadow: textShadow,
            cachedImageForURL: { cachedEmotes[$0]?.uiImage },
            placeholderImageForSize: placeholderProvider
        )
        let textSize = rendered.attributedText.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).size
        let size = CGSize(
            width: ceil(max(textSize.width, font.pointSize) + 12),
            height: ceil(max(textSize.height, font.lineHeight) + 6)
        )
        let clampedSize = CGSize(
            width: min(size.width, 4096),
            height: min(size.height, 512)
        )
        let cgImage = rasterizeTextGlyph(
            attributedText: rendered.attributedText,
            size: clampedSize,
            scale: scale,
            isVIPGradientColorful: item.isVIPGradientColorful
        )
        let cached = DanmakuSyncCachedText(
            image: cgImage,
            size: clampedSize,
            missingEmoteURLs: Set(rendered.missingImageURLs)
        )
        return (cached, rendered.missingImageURLs)
    }

    private nonisolated static func rasterizeTextGlyph(
        attributedText: NSAttributedString,
        size clampedSize: CGSize,
        scale: CGFloat,
        isVIPGradientColorful: Bool
    ) -> CGImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: clampedSize, format: format)
        let rect = CGRect(origin: .zero, size: clampedSize)
        let image = renderer.image { context in
            attributedText.draw(in: rect)
            guard isVIPGradientColorful else { return }
            let cgContext = context.cgContext
            let unshadowed = NSMutableAttributedString(attributedString: attributedText)
            unshadowed.removeAttribute(.shadow, range: NSRange(location: 0, length: unshadowed.length))
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let gradientColors: [CGColor] = [
                UIColor(red: 1.0, green: 0.42, blue: 0.62, alpha: 1.0).cgColor,
                UIColor(red: 1.0, green: 0.60, blue: 0.38, alpha: 1.0).cgColor,
                UIColor(red: 1.0, green: 0.82, blue: 0.40, alpha: 1.0).cgColor,
            ]
            guard let gradient = CGGradient(
                colorsSpace: colorSpace,
                colors: gradientColors as CFArray,
                locations: [0.0, 0.52, 1.0]
            ) else { return }

            cgContext.saveGState()
            cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
            unshadowed.draw(in: rect)
            cgContext.setBlendMode(.sourceAtop)
            cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: clampedSize.height * 0.5),
                end: CGPoint(x: clampedSize.width, y: clampedSize.height * 0.5),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
            cgContext.endTransparencyLayer()
            cgContext.restoreGState()
        }
        if let cgImage = image.cgImage {
            return cgImage
        }
        return UIGraphicsImageRenderer(size: .init(width: 1, height: 1)).image { _ in
            UIColor.clear.setFill()
            UIBezierPath(rect: CGRect(x: 0, y: 0, width: 1, height: 1)).fill()
        }.cgImage!
    }
}
