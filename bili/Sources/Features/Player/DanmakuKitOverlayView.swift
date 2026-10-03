import DanmakuKit
import UIKit

@MainActor
final class DanmakuKitOverlayView: UIView {
    private let renderer = DanmakuView(frame: .zero)
    private var displayLink: CADisplayLink?

    private var items: [DanmakuItem] = []
    private var itemsRevision: Int?
    private var currentTime: TimeInterval = 0
    private var anchorPlaybackTime: TimeInterval = 0
    private var anchorHostTime = CACurrentMediaTime()
    private var hasPlaybackAnchor = false
    private var lastTimelineTime: TimeInterval?
    private var clearedThroughPlaybackTime: TimeInterval?
    private var playbackRate = 1.0
    private var isPlaying = false
    private var isEnabled = true
    private var hasPresentedPlayback = false
    private var isLoadShedding = false
    private var settings: DanmakuSettings = .default
    private var topInset: CGFloat = 0
    private var bottomInset: CGFloat = 0
    private var isLayoutTransitioning = false
    private var needsLayoutRebuild = false
    private var displayedUntil: [String: TimeInterval] = [:]
    private var emoteLoadTasks: [URL: Task<Void, Never>] = [:]
    private var lastLayoutSize = CGSize.zero

    #if DEBUG
    var debugMaximumActiveCount: Int?
    #endif

    var isLoadSheddingValue: Bool { isLoadShedding }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = true
        isUserInteractionEnabled = false
        renderer.isUserInteractionEnabled = false
        renderer.enableCellReusable = false
        renderer.enableTopDanmaku = true
        renderer.enableBottomDanmaku = true
        addSubview(renderer)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    deinit {
        emoteLoadTasks.values.forEach { $0.cancel() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateDisplayLinkState()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let sizeChanged = abs(bounds.width - lastLayoutSize.width) > 1
            || abs(bounds.height - lastLayoutSize.height) > 1
        configureRenderer()
        guard sizeChanged else { return }
        lastLayoutSize = bounds.size
        guard sizeIsUsable else { return }
        if isLayoutTransitioning {
            needsLayoutRebuild = true
        } else if shouldRender {
            rebuildVisibleItems(at: effectivePlaybackTime(), reason: "viewport")
        }
    }

    func apply(
        items newItems: [DanmakuItem],
        itemsRevision newRevision: Int,
        currentTime newCurrentTime: TimeInterval,
        isPlaying newIsPlaying: Bool,
        playbackRate newPlaybackRate: Double,
        isEnabled newIsEnabled: Bool,
        hasPresentedPlayback newHasPresentedPlayback: Bool,
        isLoadShedding newIsLoadShedding: Bool,
        settings newSettings: DanmakuSettings,
        topInset newTopInset: CGFloat,
        bottomInset newBottomInset: CGFloat
    ) {
        let normalizedSettings = newSettings.normalized
        let previousShouldRender = shouldRender
        let previousTime = currentTime
        let previousEffectiveTime = effectivePlaybackTime()
        let previousIsPlaying = isPlaying
        let previousPlaybackRate = playbackRate
        let settingsChanged = settings != normalizedSettings
            || abs(topInset - max(0, newTopInset)) > 0.5
            || abs(bottomInset - max(0, newBottomInset)) > 0.5
        let itemsChanged = itemsRevision != newRevision

        items = newItems.filter { $0.time.isFinite && $0.fontSize.isFinite }.sorted {
            if $0.time != $1.time { return $0.time < $1.time }
            return $0.id < $1.id
        }
        itemsRevision = newRevision
        currentTime = max(0, newCurrentTime.isFinite ? newCurrentTime : 0)
        isPlaying = newIsPlaying
        playbackRate = max(0.1, newPlaybackRate.isFinite ? newPlaybackRate : 1)
        isEnabled = newIsEnabled
        hasPresentedPlayback = newHasPresentedPlayback
        isLoadShedding = newIsLoadShedding
        settings = normalizedSettings
        topInset = max(0, newTopInset)
        bottomInset = max(0, newBottomInset)
        configureRenderer()

        let clockAdvanced = abs(currentTime - previousTime) >= 0.05
        if !hasPlaybackAnchor || clockAdvanced {
            syncPlaybackAnchor(to: currentTime)
        } else if previousIsPlaying != isPlaying {
            let transitionTime = isPlaying ? currentTime : previousEffectiveTime
            currentTime = transitionTime
            syncPlaybackAnchor(to: transitionTime)
        } else if abs(previousPlaybackRate - playbackRate) > 0.001 {
            syncPlaybackAnchor(to: previousEffectiveTime)
        }
        let playbackTime = effectivePlaybackTime()

        guard shouldRender else {
            renderer.pause()
            renderer.clean()
            displayedUntil.removeAll(keepingCapacity: true)
            lastTimelineTime = playbackTime
            DanmakuRendererDiagnostics.shared.recordDanmakuKitActiveItems(0)
            updatePlaybackState()
            return
        }

        if isLayoutTransitioning {
            if currentTime + 0.2 < previousEffectiveTime {
                clearedThroughPlaybackTime = nil
            }
            clearDanmakuThrough(playbackTime)
            needsLayoutRebuild = true
            lastTimelineTime = playbackTime
            updatePlaybackState()
            return
        }

        let jumped = hasPlaybackAnchor
            && (currentTime + 0.2 < previousEffectiveTime
                || (clockAdvanced && abs(currentTime - previousEffectiveTime) > seekJumpThreshold))
        if jumped {
            clearedThroughPlaybackTime = nil
        }
        if !previousShouldRender || settingsChanged || jumped {
            let reason = !previousShouldRender ? "render-start" : (jumped ? "media-jump" : "settings-or-insets")
            rebuildVisibleItems(at: playbackTime, reason: reason)
        } else {
            if itemsChanged {
                synchronizeNewlyLoadedItems(at: playbackTime)
            }
            advanceTimeline(from: lastTimelineTime ?? previousEffectiveTime, to: playbackTime)
        }
        updatePlaybackState()
    }

    func setLayoutTransitioning(_ transitioning: Bool) {
        guard isLayoutTransitioning != transitioning else { return }
        isLayoutTransitioning = transitioning
        if transitioning {
            needsLayoutRebuild = false
            clearDanmakuThrough(effectivePlaybackTime())
            renderer.pause()
            renderer.clean()
            displayedUntil.removeAll(keepingCapacity: true)
            lastTimelineTime = effectivePlaybackTime()
            DanmakuRendererDiagnostics.shared.recordDanmakuKitActiveItems(0)
            updateDisplayLinkState()
            return
        }
        clearDanmakuThrough(effectivePlaybackTime())
        guard needsLayoutRebuild || abs(bounds.width - lastLayoutSize.width) > 1
                || abs(bounds.height - lastLayoutSize.height) > 1
        else {
            updatePlaybackState()
            return
        }
        needsLayoutRebuild = false
        lastLayoutSize = bounds.size
        configureRenderer()
        rebuildVisibleItems(at: effectivePlaybackTime(), reason: "layout-transition")
    }

    func synchronizePlaybackTime(_ time: TimeInterval, force: Bool = false) {
        let sanitizedTime = max(0, time.isFinite ? time : 0)
        let previousEffectiveTime = effectivePlaybackTime()
        let previousRawTime = currentTime
        currentTime = sanitizedTime
        let clockAdvanced = abs(sanitizedTime - previousRawTime) >= 0.05
        if force || !hasPlaybackAnchor || clockAdvanced {
            syncPlaybackAnchor(to: sanitizedTime)
        }
        let playbackTime = effectivePlaybackTime()
        guard shouldRender else {
            lastTimelineTime = playbackTime
            return
        }
        if isLayoutTransitioning {
            if sanitizedTime + 0.2 < previousEffectiveTime {
                clearedThroughPlaybackTime = nil
            }
            clearDanmakuThrough(playbackTime)
            needsLayoutRebuild = true
            lastTimelineTime = playbackTime
            return
        }

        let jumped = force
            || sanitizedTime + 0.2 < previousEffectiveTime
            || (clockAdvanced && abs(sanitizedTime - previousEffectiveTime) > seekJumpThreshold)
        if jumped {
            clearedThroughPlaybackTime = nil
            rebuildVisibleItems(at: playbackTime, reason: force ? "forced-sync" : "media-jump")
        } else {
            advanceTimeline(from: lastTimelineTime ?? previousEffectiveTime, to: playbackTime)
        }
        updatePlaybackState()
    }

    func stop() {
        stopDisplayLink()
        renderer.stop()
        renderer.clean()
        emoteLoadTasks.values.forEach { $0.cancel() }
        emoteLoadTasks.removeAll(keepingCapacity: true)
        displayedUntil.removeAll(keepingCapacity: true)
        lastTimelineTime = nil
        clearedThroughPlaybackTime = nil
        hasPlaybackAnchor = false
        DanmakuRendererDiagnostics.shared.recordDanmakuKitActiveItems(0)
    }

    private var shouldRender: Bool {
        isEnabled && hasPresentedPlayback && !items.isEmpty && sizeIsUsable
    }

    private var sizeIsUsable: Bool {
        renderer.bounds.width > 20 && renderer.bounds.height > 20
    }

    private var seekJumpThreshold: TimeInterval {
        max(1.25, 0.7 * playbackRate)
    }

    private var maximumDisplayDuration: TimeInterval {
        bounds.width > 640 ? 8.4 : 7.2
    }

    private var lateDataEntryGracePeriod: TimeInterval {
        min(1.5, max(0.45, 0.6 * playbackRate))
    }

    private func displayDuration(for item: DanmakuItem) -> TimeInterval {
        DanmakuRenderPolicy.duration(for: item, viewportWidth: bounds.width)
    }

    private func configureRenderer() {
        let topPadding = topInset + CGFloat(settings.danmakuKit.topPadding)
        let bottomPadding = bottomInset + CGFloat(settings.danmakuKit.bottomPadding)
        let clampedTopPadding = min(max(topPadding, 0), bounds.height)
        let clampedBottomPadding = min(max(bottomPadding, 0), max(0, bounds.height - clampedTopPadding))
        // Use the inset content frame so top and bottom lanes stay clear of player controls.
        renderer.frame = CGRect(
            x: 0,
            y: clampedTopPadding,
            width: bounds.width,
            height: max(0, bounds.height - clampedTopPadding - clampedBottomPadding)
        )
        renderer.displayArea = CGFloat(settings.danmakuKit.displayArea.fraction)
        renderer.paddingTop = 0
        renderer.paddingBottom = 0
        renderer.trackHeight = CGFloat(settings.danmakuKit.trackHeight)
        renderer.isOverlap = settings.danmakuKit.allowsDanmakuOverlap
        renderer.enableFloatingDanmaku = settings.danmakuKit.enablesFloating
        renderer.enableTopDanmaku = settings.danmakuKit.enablesTop
        renderer.enableBottomDanmaku = settings.danmakuKit.enablesBottom
        let normalizedRate = Float(playbackRate)
        if abs(renderer.playingSpeed - normalizedRate) > 0.001 {
            renderer.playingSpeed = normalizedRate
        }
    }

    private func updatePlaybackState() {
        guard shouldRender, !isLayoutTransitioning, isPlaying else {
            renderer.pause()
            updateDisplayLinkState()
            return
        }
        renderer.play()
        updateDisplayLinkState()
    }

    private var preferredFrameRateRange: CAFrameRateRange {
        let environment = PlaybackEnvironment.current
        if isLoadShedding || environment.isThermallyConstrained || environment.isLowPowerModeEnabled {
            return CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
        }
        return CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
    }

    private func updateDisplayLinkState() {
        guard shouldRender, !isLayoutTransitioning, isPlaying, window != nil else {
            stopDisplayLink()
            return
        }
        if displayLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        displayLink?.preferredFrameRateRange = preferredFrameRateRange
        displayLink?.isPaused = false
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func syncPlaybackAnchor(to time: TimeInterval) {
        anchorPlaybackTime = max(0, time.isFinite ? time : 0)
        anchorHostTime = CACurrentMediaTime()
        hasPlaybackAnchor = true
    }

    private func effectivePlaybackTime(hostTime: CFTimeInterval = CACurrentMediaTime()) -> TimeInterval {
        guard isPlaying, hasPlaybackAnchor else { return currentTime }
        let elapsed = max(0, hostTime - anchorHostTime)
        return max(0, anchorPlaybackTime + elapsed * playbackRate)
    }

    @objc private func tick(_ displayLink: CADisplayLink) {
        guard shouldRender, isPlaying, !isLayoutTransitioning else { return }
        let start = CACurrentMediaTime()
        DanmakuRendererDiagnostics.shared.recordDanmakuKitDisplayLinkTick(
            timestamp: displayLink.timestamp,
            expectedInterval: displayLink.targetTimestamp - displayLink.timestamp
        )
        let time = effectivePlaybackTime(hostTime: displayLink.timestamp)
        advanceTimeline(from: lastTimelineTime ?? currentTime, to: time)
        DanmakuRendererDiagnostics.shared.recordDanmakuKitDisplayLinkWork(
            milliseconds: (CACurrentMediaTime() - start) * 1_000
        )
    }

    private func rebuildVisibleItems(at time: TimeInterval, reason: String) {
        guard shouldRender else {
            renderer.clean()
            displayedUntil.removeAll(keepingCapacity: true)
            lastTimelineTime = time
            DanmakuRendererDiagnostics.shared.recordDanmakuKitActiveItems(0)
            return
        }
        DanmakuRendererDiagnostics.shared.recordDanmakuKitRebuild(reason: reason)
        if renderer.status == .stop {
            renderer.play()
        }
        renderer.clean()
        displayedUntil.removeAll(keepingCapacity: true)

        let lowerBound = firstItemIndex(atOrAfter: time - maximumDisplayDuration)
        let upperBound = firstItemIndex(after: time)
        let maximumVisible = maximumActiveCount
        let visible = items[lowerBound..<upperBound].filter { item in
            isSupported(item)
                && time >= item.time
                && time - item.time < displayDuration(for: item)
        }
        for item in visible.suffix(maximumVisible) {
            display(
                item,
                at: time,
                source: reason == "render-start" ? "new-data" : "rebuild:\(reason)"
            )
        }
        lastTimelineTime = time
        DanmakuRendererDiagnostics.shared.recordDanmakuKitActiveItems(displayedUntil.count)
        updatePlaybackState()
    }

    private func synchronizeNewlyLoadedItems(at time: TimeInterval) {
        pruneDisplayedItems(at: time)
        let lowerBound = firstItemIndex(atOrAfter: time - maximumDisplayDuration)
        let upperBound = firstItemIndex(after: time)
        let visible = items[lowerBound..<upperBound].filter { item in
            isSupported(item) && time - item.time < displayDuration(for: item)
        }
        for item in visible.suffix(maximumActiveCount) {
            guard displayedUntil[item.id] == nil else { continue }
            display(item, at: time, source: "new-data")
        }
        DanmakuRendererDiagnostics.shared.recordDanmakuKitActiveItems(displayedUntil.count)
    }

    private func advanceTimeline(from previousTime: TimeInterval, to time: TimeInterval) {
        pruneDisplayedItems(at: time)
        guard isPlaying else {
            lastTimelineTime = time
            return
        }
        guard time > previousTime else {
            lastTimelineTime = max(previousTime, time)
            return
        }
        let startIndex = firstItemIndex(after: previousTime)
        let endIndex = firstItemIndex(after: time)
        guard startIndex < endIndex else {
            lastTimelineTime = time
            return
        }
        let maximumNewItems = isLoadShedding ? 12 : (bounds.width > 640 ? 6 : 4)
        for item in items[startIndex..<endIndex].prefix(maximumNewItems) where isSupported(item) {
            guard displayedUntil[item.id] == nil else { continue }
            display(item, at: time, source: "timeline")
        }
        lastTimelineTime = time
    }

    private func display(_ item: DanmakuItem, at time: TimeInterval, source: String) {
        if let clearedThroughPlaybackTime,
           item.time <= clearedThroughPlaybackTime {
            return
        }
        let age = max(0, time - item.time)
        let fullDuration = displayDuration(for: item)
        guard age < fullDuration else { return }
        let isLiveFloatingEntry = item.isScrolling && isPlaying
            && (source == "timeline" || source == "new-data")
        guard !isLiveFloatingEntry || age <= lateDataEntryGracePeriod else {
            DanmakuRendererDiagnostics.shared.recordDanmakuKitEntry(
                identifier: item.id,
                path: "late-drop",
                age: age,
                source: source,
                activeItems: displayedUntil.count
            )
            return
        }
        let isRecentFloatingEntry = isLiveFloatingEntry
        let displayTime = isRecentFloatingEntry ? max(0.25, fullDuration - age) : fullDuration
        let model = DanmakuKitTextCellModel(
            item: item,
            fontScale: settings.danmakuKit.fontScale,
            fontWeight: settings.danmakuKit.fontWeight,
            opacity: settings.danmakuKit.opacity,
            viewportWidth: bounds.width,
            displayTime: displayTime
        )
        if isRecentFloatingEntry {
            if renderer.status != .play {
                renderer.play()
            }
            renderer.shoot(danmaku: model)
            DanmakuRendererDiagnostics.shared.recordDanmakuKitEntry(
                identifier: item.id,
                path: "shoot",
                age: age,
                source: source,
                activeItems: displayedUntil.count + 1
            )
        } else {
            renderer.sync(danmaku: model, at: Float(min(age / fullDuration, 0.999)))
            DanmakuRendererDiagnostics.shared.recordDanmakuKitEntry(
                identifier: item.id,
                path: "sync",
                age: age,
                source: source,
                activeItems: displayedUntil.count + 1
            )
        }
        displayedUntil[item.id] = item.time + fullDuration
        loadEmotes(model.missingEmoteURLs)
    }

    private func clearDanmakuThrough(_ time: TimeInterval) {
        let sanitizedTime = max(0, time.isFinite ? time : 0)
        clearedThroughPlaybackTime = max(clearedThroughPlaybackTime ?? sanitizedTime, sanitizedTime)
    }

    private func isSupported(_ item: DanmakuItem) -> Bool {
        DanmakuRenderPolicy.supports(item, settings: settings)
    }

    private var maximumActiveCount: Int {
        #if DEBUG
        if let count = debugMaximumActiveCount { return min(max(count, 1), 600) }
        #endif
        return DanmakuRenderPolicy.maximumActiveCount(width: bounds.width, settings: settings,
            rate: playbackRate, loadShedding: isLoadShedding)
    }

    private func loadEmotes(_ urls: [URL]) {
        for url in Set(urls) where emoteLoadTasks[url] == nil {
            emoteLoadTasks[url] = Task { [weak self] in
                let image = await BiliEmoteImageStore.shared.image(for: url)
                guard !Task.isCancelled, let self else { return }
                self.emoteLoadTasks[url] = nil
                DanmakuRendererDiagnostics.shared.recordDanmakuKitEmoteImageLoad(succeeded: image != nil)
                guard image != nil else { return }
                guard self.shouldRender, !self.isLayoutTransitioning else { return }
                self.refreshVisibleEmoteCells(for: url)
            }
        }
    }

    private func refreshVisibleEmoteCells(for url: URL) {
        for cell in renderer.subviews.compactMap({ $0 as? DanmakuKitTextCell }) {
            guard let oldModel = cell.model as? DanmakuKitTextCellModel,
                  oldModel.missingEmoteURLs.contains(url)
            else { continue }
            let updatedModel = DanmakuKitTextCellModel(
                item: oldModel.item,
                fontScale: settings.danmakuKit.fontScale,
                fontWeight: settings.danmakuKit.fontWeight,
                opacity: settings.danmakuKit.opacity,
                viewportWidth: bounds.width,
                displayTime: oldModel.displayTime
            )
            guard abs(updatedModel.size.width - oldModel.size.width) < 1,
                  abs(updatedModel.size.height - oldModel.size.height) < 1
            else { continue }
            cell.model = updatedModel
            cell.redraw()
            loadEmotes(updatedModel.missingEmoteURLs)
        }
    }

    private func pruneDisplayedItems(at time: TimeInterval) {
        displayedUntil = displayedUntil.filter { $0.value > time }
        DanmakuRendererDiagnostics.shared.recordDanmakuKitActiveItems(displayedUntil.count)
    }

    private func firstItemIndex(atOrAfter time: TimeInterval) -> Int {
        var low = 0
        var high = items.count
        while low < high {
            let middle = (low + high) / 2
            if items[middle].time < time {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }

    private func firstItemIndex(after time: TimeInterval) -> Int {
        var low = 0
        var high = items.count
        while low < high {
            let middle = (low + high) / 2
            if items[middle].time <= time {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }
}
