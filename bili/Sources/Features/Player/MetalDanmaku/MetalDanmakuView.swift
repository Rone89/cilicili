import MetalKit
import UIKit

enum MetalDanmakuFrameRatePolicy {
    static func preferredFramesPerSecond(
        displayMaximum: Int,
        isLoadShedding: Bool,
        isLowPowerMode: Bool,
        isThermallyConstrained: Bool
    ) -> Int {
        guard !isLoadShedding, !isLowPowerMode, !isThermallyConstrained else { return 30 }
        return min(max(displayMaximum > 0 ? displayMaximum : 60, 30), 120)
    }
}

@MainActor
final class MetalDanmakuView: UIView, DanmakuOverlayRendering, MTKViewDelegate {
    let metalView: MTKView
    private let renderer: MetalDanmakuRenderer
    private let timeline = MetalDanmakuTimeline()
    private var configuration: DanmakuOverlayConfiguration?
    private var layouts: [String: DanmakuGlyphLayout] = [:]
    private var lastRevision = -1
    private var lastSize = CGSize.zero
    private var lastScale: CGFloat = 0
    private var anchorTime: TimeInterval = 0
    private var anchorHostTime = CACurrentMediaTime()
    private var lastRawTime: TimeInterval = 0
    private var transitioning = false
    private var suspended = false
    private var stopped = false
    var isLoadSheddingValue: Bool { configuration?.isLoadShedding ?? false }
    #if DEBUG
    var debugDiagnostics: DanmakuRendererDiagnostics? {
        didSet { renderer.debugDiagnostics = debugDiagnostics }
    }
    var debugPreferredFramesPerSecond: Int? { didSet { updateDrawLoop() } }
    private var isManualRefresh = false
    private(set) var debugManualRefreshCount = 0
    var debugMaximumActiveCount: Int?
    var debugActiveCount: Int { timeline.active.count }
    var debugActiveItemIDs: Set<String> { Set(timeline.active.map { $0.item.id }) }
    var debugRenderer: MetalDanmakuRenderer { renderer }
    var debugTimelineRevision: Int { timeline.revision }
    func debugFrames(at time: TimeInterval) -> [String: CGRect] {
        Dictionary(uniqueKeysWithValues: timeline.active.map { ($0.item.id, $0.frame(at: time)) })
    }
    #endif

    static func make() -> MetalDanmakuView? {
        guard let renderer = MetalDanmakuRenderer() else { return nil }
        return MetalDanmakuView(renderer: renderer)
    }

    private init(renderer: MetalDanmakuRenderer) {
        self.renderer = renderer
        metalView = MTKView(frame: .zero, device: renderer.device)
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        metalView.backgroundColor = .clear
        metalView.isOpaque = false
        metalView.layer.isOpaque = false
        metalView.clearColor = MTLClearColorMake(0, 0, 0, 0)
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.framebufferOnly = true
        metalView.isPaused = true
        metalView.enableSetNeedsDisplay = false
        metalView.isUserInteractionEnabled = false
        metalView.delegate = self
        metalView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(metalView)
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(suspend), name: UIApplication.willResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(activate), name: UIApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(memoryWarning), name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
    }
    required init?(coder: NSCoder) { nil }
    isolated deinit {
        metalView.isPaused = true
        metalView.delegate = nil
        NotificationCenter.default.removeObserver(self)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        metalView.frame = bounds
        let scale = window?.screen.scale ?? traitCollection.displayScale
        if bounds.size != lastSize || scale != lastScale {
            lastSize = bounds.size
            lastScale = scale
            metalView.contentScaleFactor = scale
            layouts.removeAll(keepingCapacity: true)
            configureTimeline()
            rebuild(reason: "layout-or-scale")
        }
        updateDrawLoop()
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateDrawLoop()
    }

    func apply(configuration next: DanmakuOverlayConfiguration) {
        let previousTime = effectiveTime()
        let previous = configuration
        let raw = max(0, next.currentTime.isFinite ? next.currentTime : 0)
        if previous == nil || abs(raw - lastRawTime) >= 0.05 {
            setAnchor(raw)
        } else if previous?.isPlaying != next.isPlaying || previous?.playbackRate != next.playbackRate {
            setAnchor(next.isPlaying && previous?.isPlaying == false ? raw : previousTime)
        }
        lastRawTime = raw
        configuration = next
        stopped = false
        configureTimeline()
        if previous?.itemsRevision != next.itemsRevision {
            let before = timeline.active.count
            let time = effectiveTime()
            let settingsUnchanged = previous?.settings == next.settings
                && previous?.topInset == next.topInset
                && previous?.bottomInset == next.bottomInset
            if settingsUnchanged, timeline.replaceItemsPreservingActive(next.items, at: time) {
                let retainedIDs = Set(next.items.map(\.id)).union(timeline.active.map { $0.item.id })
                layouts = layouts.filter { retainedIDs.contains($0.key) }
                traceScene("items-preserved", before: before)
            } else {
                layouts.removeAll(keepingCapacity: true)
                timeline.replaceItems(next.items, at: time, measure: measure)
                traceScene("items-replaced", before: before)
            }
            lastRevision = -1
        } else if previous?.settings != next.settings || previous?.topInset != next.topInset || previous?.bottomInset != next.bottomInset {
            layouts.removeAll(keepingCapacity: true)
            rebuild(reason: "settings-or-insets")
        } else if abs(raw - previousTime) > max(1.25, 0.7 * next.playbackRate) {
            rebuild(reason: "configuration-time-jump")
        }
        if !shouldRender {
            let before = timeline.active.count
            timeline.clear(); lastRevision = -1
            if before > 0 { traceScene("visibility-clear enabled=\(next.isEnabled) presented=\(next.hasPresentedPlayback) items=\(next.items.count)", before: before) }
        } else if previous?.isEnabled == false || previous?.hasPresentedPlayback == false { rebuild(reason: "visibility-restored") }
        updateInstances()
        updateDrawLoop()
        drawOnceIfVisible()
    }

    func synchronizePlaybackTime(_ time: TimeInterval, force: Bool = false) {
        guard time.isFinite else { return }
        let previous = effectiveTime()
        let raw = max(0, time)
        if force || abs(raw - lastRawTime) >= 0.05 { setAnchor(raw) }
        lastRawTime = raw
        if force || raw + 0.2 < previous || abs(raw - previous) > 1.25 { rebuild(reason: force ? "forced-clock-sync" : "clock-sync-jump") }
        updateInstances()
        if configuration?.isPlaying != true { drawOnceIfVisible() }
    }

    func setLayoutTransitioning(_ transitioning: Bool) {
        guard self.transitioning != transitioning else { return }
        self.transitioning = transitioning
        if transitioning {
            let before = timeline.active.count
            timeline.clear(); updateInstances()
            traceScene("layout-transition-clear", before: before)
        } else { rebuild(reason: "layout-transition-end") }
        updateDrawLoop()
        drawOnceIfVisible()
    }

    func stop() {
        let before = timeline.active.count
        stopped = true
        metalView.isPaused = true
        metalView.isHidden = true
        timeline.clear()
        traceScene("stop", before: before)
        layouts.removeAll()
        renderer.reset()
        configuration = nil
        lastRevision = -1
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }
    func draw(in view: MTKView) {
        guard !stopped, !suspended, window != nil else { return }
        let start = CACurrentMediaTime()
        let sampledTime = effectiveTime()
        if shouldRender && !transitioning {
            #if DEBUG
            let before = timeline.active.count
            let rebuildCount = timeline.rebuildCount
            #endif
            timeline.advance(to: sampledTime, measure: measure)
            #if DEBUG
            if timeline.rebuildCount != rebuildCount {
                traceScene(timeline.lastRebuildReason, before: before)
            } else if before > 0 && timeline.active.isEmpty {
                traceScene("natural-expiry", before: before)
            }
            #endif
            updateInstances()
        }
        // Admission and shader lifetime must use the same accepted clock sample.
        // Tiny player-clock corrections must not hide newly admitted glyphs.
        let presentationTime = timeline.presentationTime ?? sampledTime
        #if DEBUG
        renderer.render(view: view, time: presentationTime, preparationStartedAt: start,
                        isManualRefresh: isManualRefresh)
        #else
        renderer.render(view: view, time: presentationTime, preparationStartedAt: start)
        #endif
    }

    private var shouldRender: Bool {
        guard let c = configuration else { return false }
        return c.isEnabled && c.hasPresentedPlayback && !c.items.isEmpty && bounds.width > 20 && bounds.height > 20
    }
    private func configureTimeline() {
        guard let c = configuration else { return }
        timeline.viewport = bounds.size
        timeline.settings = c.settings.normalized
        timeline.topInset = c.topInset
        timeline.bottomInset = c.bottomInset
        timeline.maximumActiveCount = DanmakuRenderPolicy.maximumActiveCount(width: bounds.width,
            settings: c.settings, rate: c.playbackRate, loadShedding: c.isLoadShedding)
        #if DEBUG
        if let count = debugMaximumActiveCount { timeline.maximumActiveCount = min(max(count, 1), 600) }
        #endif
    }
    private func measure(_ item: DanmakuItem) -> CGSize? {
        if let layout = layouts[item.id] { return layout.size }
        guard let c = configuration,
              let layout = renderer.layout(for: item, width: bounds.width, settings: c.settings,
                                           scale: max(lastScale, 1)) else { return nil }
        layouts[item.id] = layout
        return layout.size
    }
    private func rebuild(reason: String = "explicit") {
        guard shouldRender, !transitioning else { return }
        let before = timeline.active.count
        timeline.rebuild(at: effectiveTime(), measure: measure, reason: reason)
        traceScene(reason, before: before)
        lastRevision = -1
        updateInstances()
    }
    private func traceScene(_ reason: String, before: Int) {
        #if DEBUG
        (debugDiagnostics ?? .shared).recordMetalSceneEvent(reason, time: effectiveTime(), before: before, after: timeline.active.count)
        #endif
    }
    private func updateInstances() {
        guard lastRevision != timeline.revision else { return }
        renderer.update(entries: timeline.active, layouts: layouts, opacity: timeline.settings.danmakuKit.opacity)
        lastRevision = timeline.revision
    }
    private func setAnchor(_ time: TimeInterval) {
        anchorTime = time
        anchorHostTime = CACurrentMediaTime()
    }
    private func effectiveTime() -> TimeInterval {
        guard configuration?.isPlaying == true, !suspended else { return anchorTime }
        return anchorTime + max(0, CACurrentMediaTime() - anchorHostTime) * (configuration?.playbackRate ?? 1)
    }
    private func updateDrawLoop() {
        #if DEBUG
        let wasHidden = metalView.isHidden
        #endif
        metalView.isHidden = !shouldRender || transitioning || stopped
        metalView.isPaused = metalView.isHidden || suspended || window == nil || configuration?.isPlaying != true
        #if DEBUG
        if wasHidden != metalView.isHidden {
            traceScene("hidden=\(metalView.isHidden) renderable=\(shouldRender) transitioning=\(transitioning) stopped=\(stopped)", before: timeline.active.count)
        }
        if metalView.isPaused { (debugDiagnostics ?? .shared).resetMetalCadence() }
        #endif
        let environment = PlaybackEnvironment.current
        let displayMaximumFPS = window?.screen.maximumFramesPerSecond ?? 60
        metalView.preferredFramesPerSecond = MetalDanmakuFrameRatePolicy.preferredFramesPerSecond(
            displayMaximum: displayMaximumFPS,
            isLoadShedding: isLoadSheddingValue,
            isLowPowerMode: environment.isLowPowerModeEnabled,
            isThermallyConstrained: environment.isThermallyConstrained
        )
        #if DEBUG
        if let requested = debugPreferredFramesPerSecond {
            metalView.preferredFramesPerSecond = min(metalView.preferredFramesPerSecond, max(1, requested))
        }
        #endif
    }
    private func drawOnceIfVisible() {
        // The running MTKView loop will present updated state on its next tick.
        // A synchronous extra draw competes for drawables and disturbs that cadence.
        guard metalView.isPaused, !metalView.isHidden, !suspended, window != nil else { return }
        #if DEBUG
        debugManualRefreshCount += 1
        isManualRefresh = true
        defer { isManualRefresh = false }
        #endif
        metalView.draw()
    }
    @objc private func suspend() {
        setAnchor(effectiveTime())
        suspended = true
        traceScene("suspend", before: timeline.active.count)
        updateDrawLoop()
    }
    @objc private func activate() {
        suspended = false
        setAnchor(lastRawTime)
        rebuild(reason: "foreground")
        updateDrawLoop()
        drawOnceIfVisible()
    }
    @objc private func memoryWarning() {
        let before = timeline.active.count
        timeline.clear()
        traceScene("memory-warning-clear", before: before)
        layouts.removeAll()
        renderer.reset()
        lastRevision = -1
        // Refill lazily on the next valid clock/render event.
        if shouldRender { rebuild(reason: "memory-warning-refill"); drawOnceIfVisible() }
    }
}
