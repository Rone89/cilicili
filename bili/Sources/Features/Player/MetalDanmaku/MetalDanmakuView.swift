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
    private static let fontScaleSettleDuration: TimeInterval = 0.14
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
    private var stageTransitionExperimentEnabled = false
    private var stageTransitionActive = false
    private var stageSourceViewport = CGSize.zero
    private var stageTransform = MetalDanmakuStageTransform.identity
    private var videoViewport = CGRect.zero
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
    var debugStageTransitionActive: Bool { stageTransitionActive }
    var debugTimelineViewport: CGSize { timeline.viewport }
    var debugStageTransform: MetalDanmakuStageTransform { stageTransform }
    func debugFrames(at time: TimeInterval) -> [String: CGRect] {
        Dictionary(uniqueKeysWithValues: timeline.active.map { ($0.item.id, $0.frame(at: time)) })
    }
    func debugPresentedFrames(at time: TimeInterval,
                              hostTime: TimeInterval = CACurrentMediaTime()) -> [String: CGRect] {
        Dictionary(uniqueKeysWithValues: timeline.active.map { entry in
            let scale = entry.glyphScale(at: hostTime)
            let layout = layouts[entry.item.id]
            let anchorX: CGFloat = entry.item.isScrolling ? 0 : 0.5
            let anchorY: CGFloat = entry.item.isBottomAnchored ? 1 : 0
            let originX = entry.startX - entry.velocity * max(0, time - entry.item.time)
                + (1 - scale) * (layout?.size.width ?? entry.size.width) * anchorX
            let originY = entry.y + (1 - scale) * (layout?.size.height ?? entry.size.height) * anchorY
            var frame = CGRect(x: originX, y: originY,
                               width: (layout?.size.width ?? entry.size.width) * scale,
                               height: (layout?.size.height ?? entry.size.height) * scale)
            if stageTransitionActive { frame = stageTransform.map(frame) }
            frame.origin.x += videoViewport.minX
            frame.origin.y += videoViewport.minY
            return (entry.item.id, frame)
        })
    }
    func debugDisplayedFontPointSize(for id: String, at hostTime: TimeInterval) -> CGFloat? {
        guard let entry = timeline.active.first(where: { $0.item.id == id }),
              let layout = layouts[id] else { return nil }
        return layout.fontPointSize * entry.glyphScale(at: hostTime)
    }
    func debugFontScaleSettleEnd(for id: String) -> TimeInterval? {
        timeline.active.first(where: { $0.item.id == id }).flatMap { entry in
            entry.fontScaleSettleStartHostTime.map { $0 + entry.fontScaleSettleDuration }
        }
    }
    func debugFontScaleSettleStart(for id: String) -> TimeInterval? {
        timeline.active.first(where: { $0.item.id == id })?.fontScaleSettleStartHostTime
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
        let sizeChanged = bounds.size != lastSize
        let scaleChanged = scale != lastScale
        let nextVideoViewport = resolvedVideoViewport()
        let viewportChanged = nextVideoViewport != videoViewport
        videoViewport = nextVideoViewport
        if stageTransitionActive {
            updateStageTransform(logViewportChange: viewportChanged)
        }
        if sizeChanged || scaleChanged {
            lastSize = bounds.size
            lastScale = scale
            metalView.contentScaleFactor = scale
            if !stageTransitionActive {
                layouts.removeAll(keepingCapacity: true)
                configureTimeline()
                rebuild(reason: "layout-or-scale")
            }
        }
        updateDrawLoop()
        if stageTransitionActive && viewportChanged { drawOnceIfVisible() }
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
        let nextVideoViewport = resolvedVideoViewport()
        let viewportChanged = nextVideoViewport != videoViewport
        videoViewport = nextVideoViewport
        if stageTransitionActive {
            updateStageTransform(logViewportChange: viewportChanged)
        } else {
            configureTimeline()
        }
        if previous?.itemsRevision != next.itemsRevision {
            let before = timeline.active.count
            let time = effectiveTime()
            let settingsUnchanged = previous?.settings == next.settings
                && previous?.topInset == next.topInset
                && previous?.bottomInset == next.bottomInset
            if stageTransitionActive {
                timeline.replaceItemsKeepingActiveDuringStageTransition(next.items, at: time)
                let retainedIDs = Set(next.items.map(\.id)).union(timeline.active.map { $0.item.id })
                layouts = layouts.filter { retainedIDs.contains($0.key) }
                traceScene("stage-items-preserved", before: before)
            } else if settingsUnchanged, timeline.replaceItemsPreservingActive(next.items, at: time) {
                let retainedIDs = Set(next.items.map(\.id)).union(timeline.active.map { $0.item.id })
                layouts = layouts.filter { retainedIDs.contains($0.key) }
                traceScene("items-preserved", before: before)
            } else {
                layouts.removeAll(keepingCapacity: true)
                timeline.replaceItems(next.items, at: time, measure: measure)
                traceScene("items-replaced", before: before)
            }
            lastRevision = -1
        } else if !stageTransitionActive,
                  previous?.settings != next.settings || previous?.topInset != next.topInset
                    || previous?.bottomInset != next.bottomInset {
            layouts.removeAll(keepingCapacity: true)
            rebuild(reason: "settings-or-insets")
        } else if stageTransitionExperimentEnabled, !stageTransitionActive, viewportChanged {
            layouts.removeAll(keepingCapacity: true)
            configureTimeline()
            rebuild(reason: "video-viewport")
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
        if stageTransitionExperimentEnabled {
            self.transitioning = false
            if transitioning {
                beginStageTransitionIfNeeded()
            } else {
                finishStageTransitionIfNeeded()
            }
            updateDrawLoop()
            drawOnceIfVisible()
            return
        }
        if stageTransitionActive { finishStageTransitionIfNeeded() }
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
        completeFontScaleSettles(at: start)
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
        let renderStage = stageTransitionExperimentEnabled
            ? MetalDanmakuRenderStage(
                transform: stageTransitionActive ? stageTransform : .identity,
                videoViewport: videoViewport
            )
            : nil
        #if DEBUG
        renderer.render(view: view, time: presentationTime, preparationStartedAt: start,
                        isManualRefresh: isManualRefresh, stage: renderStage)
        #else
        renderer.render(view: view, time: presentationTime, preparationStartedAt: start,
                        stage: renderStage)
        #endif
    }

    private var shouldRender: Bool {
        guard let c = configuration else { return false }
        let size = stageTransitionExperimentEnabled ? videoViewport.size : bounds.size
        return c.isEnabled && c.hasPresentedPlayback && !c.items.isEmpty && size.width > 20 && size.height > 20
    }
    private func configureTimeline() {
        guard let c = configuration else { return }
        guard !stageTransitionActive else { return }
        timeline.viewport = stageTransitionExperimentEnabled ? videoViewport.size : bounds.size
        timeline.settings = c.settings.normalized
        timeline.topInset = c.topInset
        timeline.bottomInset = c.bottomInset
        timeline.maximumActiveCount = DanmakuRenderPolicy.maximumActiveCount(width: timeline.viewport.width,
            settings: c.settings, rate: c.playbackRate, loadShedding: c.isLoadShedding)
        #if DEBUG
        if let count = debugMaximumActiveCount { timeline.maximumActiveCount = min(max(count, 1), 600) }
        #endif
    }
    private func measure(_ item: DanmakuItem) -> CGSize? {
        if let layout = layouts[item.id] { return layout.size }
        guard configuration != nil,
              let layout = renderer.layout(for: item, width: timeline.viewport.width, settings: timeline.settings,
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
        renderer.update(entries: timeline.active, layouts: layouts,
                        opacity: timeline.settings.danmakuKit.opacity,
                        stageTransitionEnabled: stageTransitionExperimentEnabled)
        lastRevision = timeline.revision
    }

    func setStageTransitionExperimentEnabled(_ enabled: Bool) {
        guard stageTransitionExperimentEnabled != enabled else { return }
        if enabled, !renderer.prepareStageTransitionPipeline() {
            #if DEBUG
            print("[DanmakuStage] event=pipeline-unavailable; keeping current Metal renderer path")
            #endif
            return
        }
        if !enabled { finishStageTransitionIfNeeded() }
        let previousViewport = stageTransitionExperimentEnabled ? videoViewport.size : bounds.size
        stageTransitionExperimentEnabled = enabled
        transitioning = false
        metalView.isHidden = false
        videoViewport = resolvedVideoViewport()

        if enabled {
            let transform = MetalDanmakuStageTransform.aspectFit(from: previousViewport, into: videoViewport.size)
            timeline.rebaseActive(using: transform, at: effectiveTime())
            configureTimeline()
            normalizeActiveFonts(at: effectiveTime(), hostTime: CACurrentMediaTime())
            traceStage("enabled", transform: transform)
        } else {
            stageTransitionActive = false
            stageSourceViewport = .zero
            stageTransform = .identity
            transitioning = false
            layouts.removeAll(keepingCapacity: true)
            configureTimeline()
            rebuild(reason: "stage-experiment-disabled")
            renderer.discardStageTransitionBuffers()
            traceStage("disabled", transform: .identity)
        }
        lastRevision = -1
        updateInstances()
        updateDrawLoop()
        drawOnceIfVisible()
    }

    private func resolvedVideoViewport() -> CGRect {
        MetalDanmakuVideoViewport.aspectFit(in: bounds, aspectRatio: configuration?.videoAspectRatio)
    }

    private func beginStageTransitionIfNeeded() {
        guard !stageTransitionActive else { return }
        materializeFontScaleSettle(at: CACurrentMediaTime())
        stageTransitionActive = true
        stageSourceViewport = timeline.viewport.width > 0 && timeline.viewport.height > 0
            ? timeline.viewport : videoViewport.size
        updateStageTransform(logViewportChange: true)
        traceStage("transition-begin", transform: stageTransform)
    }

    private func updateStageTransform(logViewportChange: Bool) {
        guard stageTransitionActive else { return }
        let next = MetalDanmakuStageTransform.aspectFit(from: stageSourceViewport, into: videoViewport.size)
        guard next != stageTransform || logViewportChange else { return }
        stageTransform = next
        if logViewportChange { traceStage("viewport-change", transform: next) }
    }

    private func finishStageTransitionIfNeeded() {
        guard stageTransitionActive else { return }
        let transform = MetalDanmakuStageTransform.aspectFit(from: stageSourceViewport, into: videoViewport.size)
        let before = timeline.active.count
        timeline.rebaseActive(using: transform, at: effectiveTime())
        traceStage("transition-end", transform: transform)
        stageTransitionActive = false
        stageSourceViewport = .zero
        stageTransform = .identity
        configureTimeline()
        normalizeActiveFonts(at: effectiveTime(), hostTime: CACurrentMediaTime())
        lastRevision = -1
        updateInstances()
        traceScene("stage-transition-end tracks-updated", before: before)
        if timeline.active.isEmpty, shouldRender { rebuild(reason: "stage-transition-refill") }
    }

    private func traceStage(_ event: String, transform: MetalDanmakuStageTransform) {
        #if DEBUG
        let diagnostics = debugDiagnostics ?? .shared
        diagnostics.recordMetalSceneEvent("stage-\(event)", time: effectiveTime(),
                                          before: timeline.active.count, after: timeline.active.count)
        print("[DanmakuStage] event=\(event) experiment=\(stageTransitionExperimentEnabled) "
            + "source=\(Int(stageSourceViewport.width))x\(Int(stageSourceViewport.height)) "
            + "video=\(Int(videoViewport.width))x\(Int(videoViewport.height)) "
            + "scale=\(transform.scale) "
            + "offset=\(Int(transform.translation.x)),\(Int(transform.translation.y)) "
            + "active=\(timeline.active.count) atlasPages=\(renderer.atlas.textures.count) "
            + "rasterizations=\(renderer.atlas.rasterizationCount)")
        #endif
    }
    private func normalizeActiveFonts(at time: TimeInterval, hostTime: TimeInterval) {
        let previousLayouts = layouts
        var targetLayouts: [String: DanmakuGlyphLayout] = [:]
        var pairs: [String: (previous: DanmakuGlyphLayout, target: DanmakuGlyphLayout)] = [:]
        targetLayouts.reserveCapacity(timeline.active.count)
        pairs.reserveCapacity(timeline.active.count)

        for entry in timeline.active {
            guard let target = renderer.layout(for: entry.item, width: timeline.viewport.width,
                                               settings: timeline.settings,
                                               scale: max(lastScale, 1)) else {
                if let previous = previousLayouts[entry.item.id] {
                    targetLayouts[entry.item.id] = previous
                }
                continue
            }
            targetLayouts[entry.item.id] = target
            pairs[entry.item.id] = (previousLayouts[entry.item.id] ?? target, target)
        }

        layouts = targetLayouts
        timeline.normalizeActiveFonts(at: time, hostTime: hostTime,
                                      duration: Self.fontScaleSettleDuration, layouts: pairs)
        lastRevision = -1
        #if DEBUG
        print("[DanmakuStage] event=font-normalize active=\(pairs.count) durationMs=\(Int(Self.fontScaleSettleDuration * 1_000)) "
            + "atlasPages=\(renderer.atlas.textures.count) rasterizations=\(renderer.atlas.rasterizationCount)")
        #endif
    }

    private func materializeFontScaleSettle(at hostTime: TimeInterval) {
        guard timeline.materializeFontScaleSettle(at: hostTime,
            layoutForItem: { [layouts] item in layouts[item.id] }) else { return }
        lastRevision = -1
        updateInstances()
    }

    private func completeFontScaleSettles(at hostTime: TimeInterval) {
        guard timeline.completeFontScaleSettles(at: hostTime,
            layoutForItem: { [layouts] item in layouts[item.id] }) else { return }
        lastRevision = -1
        updateInstances()
        updateDrawLoop()
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
        let fontSettleActive = timeline.hasActiveFontScaleSettle(at: CACurrentMediaTime())
        metalView.isPaused = metalView.isHidden || suspended || window == nil
            || (configuration?.isPlaying != true && !fontSettleActive)
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
