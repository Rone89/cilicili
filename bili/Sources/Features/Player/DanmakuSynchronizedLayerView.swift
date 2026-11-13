import AVFoundation
import OSLog
import UIKit

// MARK: - Timeline lane allocator

/// 时间轴记账式泳道分配。占用控制的是碰撞放置而非容量：全部泳道繁忙时选最早
/// 空闲的一条，任何来源弹幕都不会被静默丢弃。滚动泳道在 45% 时长处即可复用
/// （此时弹幕尾端已进入画布），静态泳道占用整个展示时长。
struct DanmakuSyncLaneAllocator {
    private(set) var scrollingFreeAt: [Double]
    private(set) var topFreeAt: [Double]
    private(set) var bottomFreeAt: [Double]

    init(laneCount: Int) {
        let resolvedCount = max(1, laneCount)
        scrollingFreeAt = Array(repeating: 0, count: resolvedCount)
        let staticCount = max(resolvedCount / 3, 2)
        topFreeAt = Array(repeating: 0, count: staticCount)
        bottomFreeAt = Array(repeating: 0, count: staticCount)
    }

    mutating func reserveScrollingLane(
        at startTime: Double,
        duration: Double,
        allowsOverlap: Bool
    ) -> Int? {
        if let lane = scrollingFreeAt.firstIndex(where: { $0 <= startTime }) {
            scrollingFreeAt[lane] = startTime + duration * 0.45
            return lane
        }
        guard allowsOverlap else { return nil }
        let lane = Self.earliestFreeLane(in: scrollingFreeAt)
        scrollingFreeAt[lane] = startTime + duration * 0.45
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
        pool[lane] = startTime + duration
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

private final class DanmakuSyncCachedText {
    let image: CGImage
    let size: CGSize

    init(image: CGImage, size: CGSize) {
        self.image = image
        self.size = size
    }
}

// MARK: - Synchronized-layer renderer

/// 挂在 `AVSynchronizedLayer(playerItem:)` 上的弹幕渲染后端：动画的 beginTime
/// 直接使用媒体时间，暂停/seek/倍速由 Core Animation 随媒体时钟自动呈现，
/// 主线程仅做 0.25s 一次的物化/回收排程，不做逐帧绘制。
@MainActor
final class DanmakuSynchronizedLayerView: UIView, DanmakuOverlayRendering {
    private enum DanmakuSyncMode {
        case scroll
        case top
        case bottom
    }

    private struct SyncActiveEntry {
        let layer: DanmakuSyncBulletLayer
        let startTime: Double
        let endTime: Double
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
    private static let seekResyncThreshold: Double = 1.25
    private static let recycleGrace: Double = 0.2
    private static let maximumPooledLayers = 128
    private static let baseFontSize: CGFloat = 18

    // MARK: Configuration state

    private var configuration: DanmakuOverlayConfiguration?
    private var layoutParameters: SyncLayoutParameters?
    private var viewportWidth: CGFloat { max(bounds.width, 1) }

    // MARK: Timeline state

    private weak var playbackPlayer: AVPlayer?
    private var currentItemObservation: NSKeyValueObservation?
    private var timeObserver: Any?
    private var timeJumpObserver: NSObjectProtocol?
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

    // MARK: Test hooks（@testable 使用）

    var isSyncLayerInstalled: Bool { synchronizedLayer != nil }
    var activeDanmakuCount: Int { activeEntries.count }
    var pooledLayerCount: Int { layerPool.count }

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

    deinit {
        MainActor.assumeIsolated {
            teardownRendering()
        }
    }

    // MARK: DanmakuOverlayRendering

    func apply(configuration: DanmakuOverlayConfiguration) {
        let previousParameters = layoutParameters
        self.configuration = configuration
        isLoadSheddingValue = configuration.isLoadShedding

        let parameters = resolveLayoutParameters(for: configuration)
        let parametersChanged = parameters != previousParameters
        if parametersChanged {
            layoutParameters = parameters
            rebuildAllocatorIfNeeded(parameters: parameters)
        }
        applyContainerOpacity(parameters: parameters)

        guard configuration.isEnabled, configuration.hasPresentedPlayback else {
            sortedItems = []
            restartSchedulingAtPlaybackTime()
            updateRenderingActivity()
            return
        }

        // 窗口滑动（每 8s 重算 + 状态变化）走增量合并：飞行中子弹保留，
        // 不清场。全量重放仅限首次、泳道几何变化与禁用切换。
        let incoming = configuration.items.sorted { $0.time < $1.time }
        let merged = Self.mergedById(current: sortedItems, incoming: incoming)
        let itemsChanged = merged != sortedItems
        sortedItems = merged

        if parametersChanged || sortedItems.isEmpty {
            restartSchedulingAtPlaybackTime()
        } else if itemsChanged {
            positionCursor(at: resolvedPlaybackTime())
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
            scheduleLayoutResynchronization()
        }
    }

    func stop() {
        teardownRendering()
    }

    func attachPlaybackPlayer(_ player: AVPlayer?) {
        guard playbackPlayer !== player else { return }
        playbackPlayer = player
        currentItemObservation?.invalidate()
        currentItemObservation = nil
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
        teardownSynchronizedLayer()
        if let timeObserver, let player = playbackPlayer {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        currentItemObservation?.invalidate()
        currentItemObservation = nil
        layoutResynchronizationWork?.cancel()
        layoutResynchronizationWork = nil
        lastObservedPlaybackTime = nil
    }

    // MARK: Synchronized layer lifecycle

    private func installSynchronizedLayerIfNeeded(for item: AVPlayerItem?) {
        if let synchronizedLayer, synchronizedLayer.playerItem === item { return }
        teardownSynchronizedLayer()
        guard let item else { return }

        let syncLayer = AVSynchronizedLayer(playerItem: item)
        syncLayer.frame = bounds
        syncLayer.masksToBounds = true
        let container = CALayer()
        container.frame = bounds
        container.actions = [
            "position": NSNull(),
            "bounds": NSNull(),
            "opacity": NSNull(),
        ]
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
                self?.resynchronizePresentation()
            }
        }
        restartSchedulingAtPlaybackTime()
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

    private func addScheduler(to player: AVPlayer) {
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
           now + 0.05 < lastObservedPlaybackTime
                || now - lastObservedPlaybackTime > Self.seekResyncThreshold {
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
        while cursor < sortedItems.count, sortedItems[cursor].time <= horizon {
            let item = sortedItems[cursor]
            cursor += 1
            guard DanmakuRenderPolicy.supports(item, settings: configuration.settings) else { continue }
            guard !materializedAheadIds.contains(item.id) else { continue }
            guard activeEntries.count < maximumActiveCount else { return }
            materialize(
                item,
                parameters: parameters,
                configuration: configuration,
                currentTime: currentTime
            )
            materializedAheadIds.insert(item.id)
        }
    }

    private func materialize(
        _ item: DanmakuItem,
        parameters: SyncLayoutParameters,
        configuration: DanmakuOverlayConfiguration,
        currentTime: Double
    ) {
        guard synchronizedLayer != nil, containerLayer != nil else { return }
        let mode: DanmakuSyncMode
        let duration: Double
        if item.isTopAnchored {
            mode = .top
            duration = DanmakuRenderPolicy.duration(for: item, viewportWidth: viewportWidth)
        } else if item.isBottomAnchored {
            mode = .bottom
            duration = DanmakuRenderPolicy.duration(for: item, viewportWidth: viewportWidth)
        } else {
            mode = .scroll
            duration = DanmakuRenderPolicy.duration(for: item, viewportWidth: viewportWidth)
        }
        let startTime = max(0, item.time)
        let endTime = startTime + duration
        guard endTime > currentTime - Self.recycleGrace else { return }

        let allowsOverlap = configuration.settings.danmakuKit.allowsDanmakuOverlap
        let lane: Int?
        switch mode {
        case .scroll:
            lane = laneAllocator.reserveScrollingLane(
                at: startTime, duration: duration, allowsOverlap: allowsOverlap
            )
        case .top:
            lane = laneAllocator.reserveTopLane(
                at: startTime, duration: duration, allowsOverlap: allowsOverlap
            )
        case .bottom:
            lane = laneAllocator.reserveBottomLane(
                at: startTime, duration: duration, allowsOverlap: allowsOverlap
            )
        }
        guard let lane else { return }

        let bulletLayer = dequeueLayer()
        let cached = cachedText(for: item, configuration: configuration)
        bulletLayer.configure(
            image: cached.image,
            size: cached.size,
            contentsScale: window?.windowScene?.screen.scale ?? UIScreen.main.scale
        )
        containerLayer?.addSublayer(bulletLayer)
        configureAnimations(
            on: bulletLayer,
            cached: cached,
            mode: mode,
            lane: lane,
            parameters: parameters,
            configuration: configuration,
            startTime: startTime,
            duration: duration
        )
        activeEntries.append(SyncActiveEntry(layer: bulletLayer, startTime: startTime, endTime: endTime))
    }

    // MARK: Animation construction

    private func configureAnimations(
        on layer: DanmakuSyncBulletLayer,
        cached: DanmakuSyncCachedText,
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
            let startX = contentFrame.maxX + cached.size.width / 2
            let endX = contentFrame.minX - cached.size.width / 2
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
        let expired = activeEntries.filter { $0.endTime + Self.recycleGrace <= now }
        guard !expired.isEmpty else { return }
        activeEntries.removeAll { entry in
            expired.contains(where: { $0.layer === entry.layer })
        }
        for entry in expired {
            recycleLayer(entry.layer)
        }
    }

    private func recycleAllActiveLayers() {
        for entry in activeEntries {
            recycleLayer(entry.layer)
        }
        activeEntries.removeAll()
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
        synchronizedLayer?.frame = bounds
        containerLayer?.frame = bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        guard abs(lastLayoutSize.width - bounds.width) > 0.5
                || abs(lastLayoutSize.height - bounds.height) > 0.5 else {
            return
        }
        lastLayoutSize = bounds.size
        layoutParameters = configuration.map { resolveLayoutParameters(for: $0) }
        scheduleLayoutResynchronization()
    }

    private func scheduleLayoutResynchronization() {
        guard isRenderingActive else { return }
        layoutResynchronizationWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.layoutResynchronizationWork = nil
            self.resynchronizePresentation()
        }
        layoutResynchronizationWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    // MARK: Layout parameters

    private func resolveLayoutParameters(for configuration: DanmakuOverlayConfiguration) -> SyncLayoutParameters {
        let settings = configuration.settings.normalized
        let topPadding = configuration.topInset + CGFloat(settings.danmakuKit.topPadding)
        let bottomPadding = configuration.bottomInset + CGFloat(settings.danmakuKit.bottomPadding)
        let clampedTopPadding = min(max(topPadding, 0), bounds.height)
        let clampedBottomPadding = min(max(bottomPadding, 0), max(0, bounds.height - clampedTopPadding))
        let contentFrame = CGRect(
            x: 0,
            y: clampedTopPadding,
            width: bounds.width,
            height: max(0, bounds.height - clampedTopPadding - clampedBottomPadding)
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

    private func cachedText(
        for item: DanmakuItem,
        configuration: DanmakuOverlayConfiguration
    ) -> DanmakuSyncCachedText {
        let settings = configuration.settings.normalized
        let key = "\(item.text)|\(item.color)|\(Int(item.fontSize))|\(item.mode)|\(settings.danmakuKit.fontWeight)|\(settings.danmakuKit.fontScale)" as NSString
        if let cached = textCache.object(forKey: key) {
            return cached
        }
        let cached = makeTextBitmap(for: item, configuration: configuration)
        textCache.setObject(cached, forKey: key, cost: cached.image.bytesPerRow * cached.image.height)
        return cached
    }

    private func makeTextBitmap(
        for item: DanmakuItem,
        configuration: DanmakuOverlayConfiguration
    ) -> DanmakuSyncCachedText {
        let settings = configuration.settings.normalized
        let viewportWidth = max(viewportWidth, 1)
        let font = DanmakuRenderPolicy.font(
            for: item,
            viewportWidth: viewportWidth,
            scale: settings.danmakuKit.fontScale,
            weight: settings.danmakuKit.fontWeight
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
        let rendered = DanmakuKitTextCellModel.render(
            item.text,
            emotes: item.inlineEmotes,
            font: font,
            color: color,
            shadow: textShadow
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
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = window?.windowScene?.screen.scale ?? UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(size: clampedSize, format: format)
        let image = renderer.image { _ in
            rendered.attributedText.draw(
                in: CGRect(origin: .zero, size: clampedSize)
            )
        }
        guard let cgImage = image.cgImage else {
            return DanmakuSyncCachedText(
                image: UIGraphicsImageRenderer(size: .init(width: 1, height: 1)).image { _ in
                    UIColor.clear.setFill()
                    UIBezierPath(rect: CGRect(x: 0, y: 0, width: 1, height: 1)).fill()
                }.cgImage ?? UIImage().cgImage!,
                size: CGSize(width: 1, height: 1)
            )
        }
        return DanmakuSyncCachedText(image: cgImage, size: clampedSize)
    }
}
