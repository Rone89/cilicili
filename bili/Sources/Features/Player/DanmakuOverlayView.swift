import Combine
import SwiftUI
import UIKit

struct DanmakuOverlayView: UIViewRepresentable {
    fileprivate struct ConfigurationSignature: Equatable {
        let itemsRevision: Int
        let currentTimeBucket: Int?
        let isPlaying: Bool
        let playbackRateTenths: Int
        let isEnabled: Bool
        let hasPresentedPlayback: Bool
        let isLoadShedding: Bool
        let settings: DanmakuSettings
        let topInsetTenths: Int
        let bottomInsetTenths: Int

        init(
            itemsRevision: Int,
            currentTime: TimeInterval,
            usesExternalClock: Bool,
            isPlaying: Bool,
            playbackRate: Double,
            isEnabled: Bool,
            hasPresentedPlayback: Bool,
            isLoadShedding: Bool,
            settings: DanmakuSettings,
            topInset: CGFloat,
            bottomInset: CGFloat
        ) {
            self.itemsRevision = itemsRevision
            // When a PlayerPlaybackClock is bound, UIKit receives time ticks directly.
            // Without one, keep a coarse time bucket so live-style callers can resync.
            currentTimeBucket = usesExternalClock ? nil : Int(max(0, currentTime) * 2)
            self.isPlaying = isPlaying
            playbackRateTenths = Int((max(playbackRate, 0.1) * 10).rounded())
            self.isEnabled = isEnabled
            self.hasPresentedPlayback = hasPresentedPlayback
            self.isLoadShedding = isLoadShedding
            self.settings = settings.normalized
            topInsetTenths = Int((max(0, topInset) * 10).rounded())
            bottomInsetTenths = Int((max(0, bottomInset) * 10).rounded())
        }
    }

    let items: [DanmakuItem]
    let itemsRevision: Int
    let currentTime: TimeInterval
    let isPlaying: Bool
    let playbackRate: Double
    let isEnabled: Bool
    let hasPresentedPlayback: Bool
    let isLoadShedding: Bool
    let settings: DanmakuSettings
    let topInset: CGFloat
    let bottomInset: CGFloat
    let isLayoutTransitioning: Bool
    let playbackClock: PlayerPlaybackClock?
    let onPlaybackTime: ((TimeInterval, Bool) -> Void)?

    init(
        items: [DanmakuItem],
        itemsRevision: Int,
        currentTime: TimeInterval = 0,
        isPlaying: Bool,
        playbackRate: Double,
        isEnabled: Bool,
        hasPresentedPlayback: Bool,
        isLoadShedding: Bool = false,
        settings: DanmakuSettings,
        topInset: CGFloat,
        bottomInset: CGFloat,
        isLayoutTransitioning: Bool = false,
        playbackClock: PlayerPlaybackClock? = nil,
        onPlaybackTime: ((TimeInterval, Bool) -> Void)? = nil
    ) {
        self.items = items
        self.itemsRevision = itemsRevision
        self.currentTime = currentTime
        self.isPlaying = isPlaying
        self.playbackRate = playbackRate
        self.isEnabled = isEnabled
        self.hasPresentedPlayback = hasPresentedPlayback
        self.isLoadShedding = isLoadShedding
        self.settings = settings
        self.topInset = topInset
        self.bottomInset = bottomInset
        self.isLayoutTransitioning = isLayoutTransitioning
        self.playbackClock = playbackClock
        self.onPlaybackTime = onPlaybackTime
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> DanmakuAnimationOverlayView {
        let view = DanmakuAnimationOverlayView()
        view.setLayoutTransitioning(isLayoutTransitioning)
        let resolvedCurrentTime = playbackClock?.currentTime ?? currentTime
        let signature = configurationSignature(resolvedCurrentTime: resolvedCurrentTime)
        view.apply(
            items: items,
            itemsRevision: itemsRevision,
            currentTime: resolvedCurrentTime,
            isPlaying: isPlaying,
            playbackRate: playbackRate,
            isEnabled: isEnabled,
            hasPresentedPlayback: hasPresentedPlayback,
            isLoadShedding: isLoadShedding,
            settings: settings,
            topInset: topInset,
            bottomInset: bottomInset
        )
        context.coordinator.markApplied(signature)
        context.coordinator.bind(clock: playbackClock, uiView: view, onPlaybackTime: onPlaybackTime)
        return view
    }

    func updateUIView(_ uiView: DanmakuAnimationOverlayView, context: Context) {
        if isLayoutTransitioning {
            uiView.setLayoutTransitioning(true)
        }
        let resolvedCurrentTime = playbackClock?.currentTime ?? currentTime
        let signature = configurationSignature(resolvedCurrentTime: resolvedCurrentTime)
        if context.coordinator.shouldApply(signature) {
            uiView.apply(
                items: items,
                itemsRevision: itemsRevision,
                currentTime: resolvedCurrentTime,
                isPlaying: isPlaying,
                playbackRate: playbackRate,
                isEnabled: isEnabled,
                hasPresentedPlayback: hasPresentedPlayback,
                isLoadShedding: isLoadShedding,
                settings: settings,
                topInset: topInset,
                bottomInset: bottomInset
            )
            context.coordinator.markApplied(signature)
        }
        if !isLayoutTransitioning {
            uiView.setLayoutTransitioning(false)
        }
        context.coordinator.bind(clock: playbackClock, uiView: uiView, onPlaybackTime: onPlaybackTime)
    }

    private func configurationSignature(resolvedCurrentTime: TimeInterval) -> ConfigurationSignature {
        ConfigurationSignature(
            itemsRevision: itemsRevision,
            currentTime: resolvedCurrentTime,
            usesExternalClock: playbackClock != nil,
            isPlaying: isPlaying,
            playbackRate: playbackRate,
            isEnabled: isEnabled,
            hasPresentedPlayback: hasPresentedPlayback,
            isLoadShedding: isLoadShedding,
            settings: settings,
            topInset: topInset,
            bottomInset: bottomInset
        )
    }

    static func dismantleUIView(_ uiView: DanmakuAnimationOverlayView, coordinator: Coordinator) {
        coordinator.unbind()
        uiView.stop()
    }

    @MainActor
    final class Coordinator {
        private weak var boundClock: PlayerPlaybackClock?
        private var clockCancellable: AnyCancellable?
        private var onPlaybackTime: ((TimeInterval, Bool) -> Void)?
        private var lastReportedPlaybackSecond: Int?
        private var isLoadShedding = false
        private var lastAppliedSignature: ConfigurationSignature?

        fileprivate func shouldApply(_ signature: ConfigurationSignature) -> Bool {
            lastAppliedSignature != signature
        }

        fileprivate func markApplied(_ signature: ConfigurationSignature) {
            lastAppliedSignature = signature
        }

        func bind(
            clock: PlayerPlaybackClock?,
            uiView: DanmakuAnimationOverlayView,
            onPlaybackTime: ((TimeInterval, Bool) -> Void)?
        ) {
            self.onPlaybackTime = onPlaybackTime
            self.isLoadShedding = uiView.isLoadShedding
            guard boundClock !== clock else { return }

            clockCancellable?.cancel()
            boundClock = clock

            guard let clock else { return }
            uiView.synchronizePlaybackTime(clock.currentTime, force: true)
            reportPlaybackTime(clock.currentTime, force: true)
            clockCancellable = clock.$currentTime
                .removeDuplicates { abs($0 - $1) < 0.05 }
                .sink { [weak self, weak uiView] time in
                    uiView?.synchronizePlaybackTime(time)
                    self?.reportPlaybackTime(time)
                }
        }

        func unbind() {
            clockCancellable?.cancel()
            clockCancellable = nil
            boundClock = nil
            lastReportedPlaybackSecond = nil
            lastAppliedSignature = nil
            onPlaybackTime = nil
        }

        private func reportPlaybackTime(_ playbackTime: TimeInterval, force: Bool = false) {
            guard let onPlaybackTime else { return }
            let sanitizedTime = max(0, playbackTime)
            let secondBucket = Int(sanitizedTime.rounded(.down))
            guard force || lastReportedPlaybackSecond != secondBucket else { return }
            lastReportedPlaybackSecond = secondBucket
            onPlaybackTime(sanitizedTime, isLoadShedding)
        }
    }
}

final class DanmakuAnimationOverlayView: UIView {
    private static let scrollingAnimationKey = "danmaku.scroll"

    private enum RenderImageFactory {
        nonisolated static func make(_ request: RenderImageRequest) -> UIImage {
            let font = UIFont.systemFont(
                ofSize: request.fontSize,
                weight: request.fontWeight.uiFontWeight
            )
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            paragraphStyle.lineBreakMode = .byClipping
            let attributedText = NSAttributedString(
                string: request.text,
                attributes: [
                    .font: font,
                    .foregroundColor: UIColor.danmakuRGB(request.color)
                        .withAlphaComponent(request.opacity),
                    .paragraphStyle: paragraphStyle
                ]
            )
            let format = UIGraphicsImageRendererFormat()
            format.scale = request.scale
            format.opaque = false
            let renderer = UIGraphicsImageRenderer(size: request.size, format: format)
            return renderer.image { rendererContext in
                rendererContext.cgContext.setShadow(
                    offset: CGSize(width: 0, height: 1),
                    blur: 1.4,
                    color: UIColor.black.withAlphaComponent(0.92).cgColor
                )
                attributedText.draw(
                    with: CGRect(origin: .zero, size: request.size),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
            }
        }
    }

    private struct ActiveEntry {
        let id: String
        let item: DanmakuItem
        let duration: TimeInterval
        let normalizedLane: CGFloat
        let labelSize: CGSize
        let fontSize: CGFloat
        let spriteLayer: CALayer
        var scrollingTrajectory: ScrollingTrajectory?
    }

    private struct CachedRenderImage {
        let image: CGImage
        let scale: CGFloat

        var pixelCost: Int {
            image.width * image.height * 4
        }
    }

    /// A trajectory is expressed in media time and captures its viewport
    /// endpoints when the entry is spawned. Rotation can then resize the
    /// parent viewport without rewriting an already visible entry's path.
    private struct ScrollingTrajectory {
        let referenceTime: TimeInterval
        let duration: TimeInterval
        let startX: CGFloat
        let endX: CGFloat

        func progress(at playbackTime: TimeInterval) -> CGFloat {
            CGFloat(min(max((playbackTime - referenceTime) / max(duration, 0.01), 0), 1))
        }
    }

    private struct LaneState {
        let releaseTime: TimeInterval
        let itemWidth: CGFloat
    }

    private struct TextMeasurementKey: Hashable {
        let text: String
        let fontSizeTenths: Int
        let fontWeight: DanmakuFontWeightOption
    }

    private struct RenderImageKey: Hashable, Sendable {
        let text: String
        let fontSizeTenths: Int
        let fontWeight: DanmakuFontWeightOption
        let color: UInt32
        let opacityThousandths: Int
        let widthPixels: Int
        let heightPixels: Int
        let scaleTenths: Int
    }

    private struct RenderImageRequest: Sendable {
        let key: RenderImageKey
        let text: String
        let fontSize: CGFloat
        let fontWeight: DanmakuFontWeightOption
        let color: UInt32
        let opacity: CGFloat
        let size: CGSize
        let scale: CGFloat
    }

    private final class PrewarmCancellationToken: @unchecked Sendable {
        private nonisolated(unsafe) let lock = NSLock()
        private nonisolated(unsafe) var cancelled = false

        nonisolated var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }

        nonisolated func cancel() {
            lock.lock()
            cancelled = true
            lock.unlock()
        }
    }

    private struct TimeBucket {
        let index: Int
        var items: [DanmakuItem]
    }

    private enum SpawnResult {
        case spawned
        case waitingForImage
        case skipped
    }

    private var items: [DanmakuItem] = []
    private var timeBuckets: [TimeBucket] = []
    private var settings: DanmakuSettings = .default
    private var currentTime: TimeInterval = 0
    private var isPlaying = false
    private var playbackRate: Double = 1
    private var isEnabled = true
    private var hasPresentedPlayback = false
    private(set) var isLoadShedding = false
    private var topInset: CGFloat = 0
    private var bottomInset: CGFloat = 0
    private var nextBucketIndex = 0
    private var nextBucketItemIndex = 0
    private var anchorPlaybackTime: TimeInterval = 0
    private var anchorHostTime = CACurrentMediaTime()
    private var correctionRate: Double = 0
    private var correctionStartHostTime: CFTimeInterval?
    private var correctionDuration: CFTimeInterval = 0
    /// Core Animation owns the per-frame motion of scrolling entries. The
    /// overlay only needs a low-frequency main-thread pass for spawning,
    /// retirement, and anchored-entry opacity.
    private var lifecycleTimer: DispatchSourceTimer?
    private var lifecycleTimerCadenceMilliseconds: Int?
    private var activeEntries: [String: ActiveEntry] = [:]
    private var pendingSpawnItems: [DanmakuItem] = []
    private var pendingSpawnIDs: Set<String> = []
    private var recycledSpriteLayers: [CALayer] = []
    private var renderPlaybackTime: TimeInterval = 0
    private var scrollingLaneStates: [Int: LaneState] = [:]
    private var textSizeCache: [TextMeasurementKey: CGSize] = [:]
    private var textSizeCacheOrder: [TextMeasurementKey] = []
    private var renderImageCache: [RenderImageKey: CachedRenderImage] = [:]
    private var renderImageCacheOrder: [RenderImageKey] = []
    private var renderImageCacheCost = 0
    private var pendingRenderImageKeys: Set<RenderImageKey> = []
    private var prewarmTokens: [RenderImageKey: PrewarmCancellationToken] = [:]
    private var pendingSpawnRetryScheduled = false
    private var lastPrewarmTimeBucket: Int?
    private let renderImagePrewarmQueue = DispatchQueue(
        label: "cc.bili.danmaku.render-prewarm",
        qos: .utility,
        autoreleaseFrequency: .workItem
    )
    private var lastLayoutSize: CGSize = .zero
    private var lastItemsRevision = -1
    private var isLayoutTransitioning = false
    private var needsContentReconciliationAfterTransition = false
    private var rotationReconciliationPending = false
    private var rotationReconciliationReady = false
    private var rotationReconciliationScheduled = false
    private var rotationReconciliationGeneration = 0
    private var rotationPlaybackTime: TimeInterval?
    private var environmentSnapshot = PlaybackEnvironment.current
    private var environmentSnapshotHostTime = CACurrentMediaTime()
    private static let environmentRefreshInterval: CFTimeInterval = 1.0
    private static let renderImageCachePixelBudget = 16 * 1024 * 1024

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = bounds.size
        guard size.width > 1, size.height > 1 else { return }
        guard abs(size.width - lastLayoutSize.width) > 1 || abs(size.height - lastLayoutSize.height) > 1 else { return }

        // Danmaku positions are derived from media time on every frame. A
        // bounds change only needs a layer-position update after the final
        // rotation size is committed. During the UIKit transition the
        // scrolling CA animations stay attached; repeatedly resolving their
        // x-coordinate against intermediate bounds causes visible jumps.
        let layoutTime = rotationPlaybackTime ?? effectivePlaybackTime()
        if shouldRenderDanmaku {
            updateActiveEntryFrames(
                at: layoutTime,
                updatesScrollingPositions: !isLayoutTransitioning && !rotationReconciliationPending
            )
        }
        lastPrewarmTimeBucket = nil
        lastLayoutSize = size
        updateDisplayLinkState()
        updateAnimationPauseState()
    }

    // Internal read-only hooks keep rotation regressions testable without
    // exposing UIKit implementation details such as UILabel subviews.
    var activeEntryIDs: Set<String> { Set(activeEntries.keys) }

    func activeEntryFontSize(for id: String) -> CGFloat? {
        activeEntries[id]?.fontSize
    }

    func activeEntryPosition(for id: String) -> CGPoint? {
        activeEntryPosition(for: id, at: renderPlaybackTime)
    }

    func activeEntryPosition(for id: String, at playbackTime: TimeInterval) -> CGPoint? {
        guard let entry = activeEntries[id] else { return nil }
        return position(for: entry, at: playbackTime, band: displayBand())
    }

    #if DEBUG
        func activeEntryLayerPosition(for id: String) -> CGPoint? {
            guard let entry = activeEntries[id] else { return nil }
            return entry.spriteLayer.presentation()?.position ?? entry.spriteLayer.position
        }
    #endif

    func activeEntryProgress(for id: String, at playbackTime: TimeInterval) -> CGFloat? {
        guard let entry = activeEntries[id], let trajectory = entry.scrollingTrajectory else {
            return nil
        }
        return trajectory.progress(at: playbackTime)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else {
            cancelPendingPrewarm()
            stopDisplayLink()
            updateAnimationPauseState()
            return
        }
        updateDisplayLinkState()
        updateAnimationPauseState()
    }

    func setLayoutTransitioning(_ isTransitioning: Bool) {
        guard isLayoutTransitioning != isTransitioning else { return }
        isLayoutTransitioning = isTransitioning
        if isTransitioning {
            // The overlay keeps its current labels and playback timeline alive
            // during the UIKit rotation.  Any size change is recorded by
            // layoutSubviews and reconciled once the system transition ends.
            needsContentReconciliationAfterTransition = false
            rotationReconciliationPending = true
            rotationReconciliationReady = false
            rotationReconciliationGeneration &+= 1
            rotationPlaybackTime = effectivePlaybackTime()
            // Keep scrolling animations attached while UIKit resizes the
            // surface. Sampling and detaching them here freezes the old
            // geometry and makes the first frame in the new orientation jump.
            return
        }

        if rotationReconciliationPending {
            scheduleRotationReconciliation()
            updateDisplayLinkState()
            updateAnimationPauseState()
            return
        }

        let didChangeSurfaceSize = abs(bounds.width - lastLayoutSize.width) > 1
            || abs(bounds.height - lastLayoutSize.height) > 1
        guard needsContentReconciliationAfterTransition || didChangeSurfaceSize else {
            updateDisplayLinkState()
            updateAnimationPauseState()
            return
        }

        needsContentReconciliationAfterTransition = false
        lastLayoutSize = bounds.size
        if shouldRenderDanmaku {
            updateActiveEntryFrames(at: effectivePlaybackTime(), updatesScrollingPositions: true)
        } else {
            clearActiveLabels()
        }
        updateDisplayLinkState()
        updateAnimationPauseState()
    }

    func apply(
        items newItems: [DanmakuItem],
        itemsRevision newItemsRevision: Int,
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
        let normalizedRate = max(newPlaybackRate, 0.1)
        let sanitizedTime = stabilizedPlaybackTime(max(0, newCurrentTime))
        let previousEffectiveTime = effectivePlaybackTime()
        let previousShouldRender = shouldRenderDanmaku
        let previousIsPlaying = isPlaying
        let didChangePlaybackRate = abs(normalizedRate - playbackRate) > 0.001
        let didChangeItems = newItemsRevision != lastItemsRevision
        let normalizedSettings = newSettings.normalized
        let didChangeRenderedSettings = abs(normalizedSettings.fontScale - settings.fontScale) > 0.001
            || abs(normalizedSettings.opacity - settings.opacity) > 0.001
            || normalizedSettings.displayArea != settings.displayArea
            || normalizedSettings.fontWeight != settings.fontWeight
        let didChangeTextMetrics = abs(normalizedSettings.fontScale - settings.fontScale) > 0.001
            || normalizedSettings.fontWeight != settings.fontWeight
        let didChangeInsets = abs(newTopInset - topInset) > 0.5 || abs(newBottomInset - bottomInset) > 0.5
        items = newItems
        if didChangeItems {
            rebuildTimeBuckets()
        }
        lastItemsRevision = newItemsRevision
        currentTime = sanitizedTime
        if !newIsPlaying {
            renderPlaybackTime = sanitizedTime
        }
        isPlaying = newIsPlaying
        playbackRate = normalizedRate
        isEnabled = newIsEnabled
        hasPresentedPlayback = newHasPresentedPlayback
        isLoadShedding = newIsLoadShedding
        settings = normalizedSettings
        topInset = max(0, newTopInset)
        bottomInset = max(0, newBottomInset)
        if didChangeTextMetrics {
            textSizeCache.removeAll(keepingCapacity: true)
            textSizeCacheOrder.removeAll(keepingCapacity: true)
        }
        if didChangeItems || didChangeRenderedSettings || didChangeInsets {
            cancelPendingPrewarm()
            lastPrewarmTimeBucket = nil
        }
        if previousIsPlaying && !newIsPlaying {
            cancelPendingPrewarm()
        }

        let currentShouldRender = shouldRenderDanmaku
        if !currentShouldRender {
            // Orientation visibility can temporarily report false while the
            // system is moving between portrait and landscape (for example
            // when portrait-only danmaku is enabled). Keep the existing layer
            // alive until the final orientation is committed; the completion
            // pass will either reconcile it or clear it if the feature remains
            // disabled.
            if isLayoutTransitioning, previousShouldRender {
                syncPlaybackAnchor(to: sanitizedTime, smoothly: true)
                return
            }
            cancelPendingPrewarm()
            clearActiveLabels()
            setNextSpawnPosition(after: sanitizedTime)
            syncPlaybackAnchor(to: sanitizedTime)
            stopDisplayLink()
            updateAnimationPauseState()
            return
        }

        let jumped = abs(sanitizedTime - previousEffectiveTime) > seekJumpThreshold || sanitizedTime + 0.2 < previousEffectiveTime
        syncPlaybackAnchor(
            to: sanitizedTime,
            smoothly: !jumped
        )

        if rotationReconciliationPending {
            if jumped {
                rotationPlaybackTime = sanitizedTime
                needsContentReconciliationAfterTransition = true
            }
            // Insets are geometry-only changes. The active entries already
            // carry their media-space font metrics and lane normalization, so
            // rebuilding them here would recreate the cached glyphs and make
            // rotation look like a font-size change.
            if !previousShouldRender || didChangeItems || didChangeRenderedSettings || didChangePlaybackRate || jumped {
                needsContentReconciliationAfterTransition = true
            }
            setNeedsLayout()
            if !isLayoutTransitioning {
                scheduleRotationReconciliation()
            }
            updateDisplayLinkState()
            updateAnimationPauseState()
            return
        }

        if isLayoutTransitioning {
            if !previousShouldRender || didChangeItems || didChangeRenderedSettings || didChangePlaybackRate || jumped {
                needsContentReconciliationAfterTransition = true
            }
            updateDisplayLinkState()
            updateAnimationPauseState()
            return
        }

        if !previousShouldRender || didChangeRenderedSettings || didChangePlaybackRate || jumped {
            rebuildVisibleItems(at: sanitizedTime, animated: newIsPlaying)
            updateDisplayLinkState()
            updateAnimationPauseState()
            return
        }

        if didChangeInsets {
            updateActiveEntryFrames(at: sanitizedTime, updatesScrollingPositions: true)
            updateDisplayLinkState()
            updateAnimationPauseState()
            return
        }

        if didChangeItems {
            if activeEntries.isEmpty {
                rebuildVisibleItems(at: sanitizedTime, animated: newIsPlaying)
            } else {
                setNextSpawnPosition(after: sanitizedTime)
            }
        }

        if previousIsPlaying != newIsPlaying && newIsPlaying {
            rebuildVisibleItems(at: sanitizedTime, animated: true)
        }

        updateDisplayLinkState()
        updateAnimationPauseState()
    }

    func stop() {
        rotationReconciliationPending = false
        rotationReconciliationReady = false
        rotationReconciliationScheduled = false
        rotationReconciliationGeneration &+= 1
        needsContentReconciliationAfterTransition = false
        rotationPlaybackTime = nil
        cancelPendingPrewarm()
        stopDisplayLink()
        clearActiveLabels()
    }

    func synchronizePlaybackTime(_ playbackTime: TimeInterval, force: Bool = false) {
        let sanitizedTime = stabilizedPlaybackTime(max(0, playbackTime))
        let previousEffectiveTime = effectivePlaybackTime()
        currentTime = sanitizedTime
        if !isPlaying {
            renderPlaybackTime = sanitizedTime
        }

        guard shouldRenderDanmaku else {
            setNextSpawnPosition(after: sanitizedTime)
            syncPlaybackAnchor(to: sanitizedTime)
            stopDisplayLink()
            updateAnimationPauseState()
            return
        }

        let drift = abs(sanitizedTime - previousEffectiveTime)
        let jumped = force || drift > seekJumpThreshold || sanitizedTime + 0.2 < previousEffectiveTime
        syncPlaybackAnchor(
            to: sanitizedTime,
            smoothly: !jumped
        )

        if rotationReconciliationPending {
            if jumped {
                rotationPlaybackTime = sanitizedTime
                needsContentReconciliationAfterTransition = true
            }
            setNeedsLayout()
            if !isLayoutTransitioning {
                scheduleRotationReconciliation()
            }
            updateDisplayLinkState()
            updateAnimationPauseState()
            return
        }

        if jumped, isLayoutTransitioning {
            needsContentReconciliationAfterTransition = true
        } else if jumped {
            rebuildVisibleItems(at: sanitizedTime, animated: isPlaying)
        }

        updateDisplayLinkState()
        updateAnimationPauseState()
    }

    private func tick() {
        guard shouldRenderDanmaku,
              isPlaying
        else { return }
        refreshEnvironmentSnapshotIfNeeded()
        let playbackTime = stabilizedPlaybackTime(effectivePlaybackTime())

        retryPendingSpawns(at: playbackTime)
        spawnDueItems(at: playbackTime)
        updateActiveEntryFrames(at: playbackTime)
        updateDisplayLinkState()
    }

    private func configureView() {
        backgroundColor = .clear
        isOpaque = false
        // The backing surface must be redrawn at its new bounds rather than
        // scaled by UIKit during rotation; scaling would visibly change the
        // cached glyph size even though the media-space font is unchanged.
        contentMode = .redraw
        clipsToBounds = true
        isUserInteractionEnabled = false
        layer.allowsGroupOpacity = false
        layer.masksToBounds = true
    }

    private var shouldRenderDanmaku: Bool {
        isEnabled && hasPresentedPlayback && !items.isEmpty && bounds.width > 20 && bounds.height > 20
    }

    private var seekJumpThreshold: TimeInterval {
        max(1.25, 0.7 * playbackRate)
    }

    private func effectivePlaybackTime(hostTime: CFTimeInterval = CACurrentMediaTime()) -> TimeInterval {
        guard isPlaying else { return currentTime }
        let elapsed = max(0, hostTime - anchorHostTime)
        guard let correctionStartHostTime else {
            return max(0, anchorPlaybackTime + elapsed * playbackRate)
        }

        let correctionElapsed = min(
            max(0, hostTime - correctionStartHostTime),
            correctionDuration
        )
        let correctedTime = max(
            0,
            anchorPlaybackTime
                + elapsed * playbackRate
                + correctionElapsed * correctionRate
        )
        if hostTime >= correctionStartHostTime + correctionDuration {
            // `targetTimestamp` is usually slightly in the future. Commit
            // the new anchor at real time so a synchronous state update cannot
            // temporarily see a future anchor and pause for one frame.
            let commitHostTime = min(hostTime, CACurrentMediaTime())
            let commitElapsed = max(0, commitHostTime - anchorHostTime)
            let commitCorrectionElapsed = min(
                max(0, commitHostTime - correctionStartHostTime),
                correctionDuration
            )
            anchorPlaybackTime = max(
                0,
                anchorPlaybackTime
                    + commitElapsed * playbackRate
                    + commitCorrectionElapsed * correctionRate
            )
            anchorHostTime = commitHostTime
            correctionRate = 0
            self.correctionStartHostTime = nil
            correctionDuration = 0
        }
        return correctedTime
    }

    private func stabilizedPlaybackTime(_ candidate: TimeInterval) -> TimeInterval {
        candidate
    }

    private func syncPlaybackAnchor(to playbackTime: TimeInterval, smoothly: Bool = false) {
        let now = CACurrentMediaTime()
        guard smoothly, isPlaying else {
            anchorPlaybackTime = max(0, playbackTime)
            anchorHostTime = now
            correctionRate = 0
            correctionStartHostTime = nil
            correctionDuration = 0
            return
        }

        // Player samples are sparse and quantized. Keep the render clock
        // continuous and correct phase with a short rate adjustment instead
        // of resetting the anchor on every sample (which creates a visible
        // one-frame hold or forward jump).
        let projectedTime = effectivePlaybackTime(hostTime: now)
        let correction = playbackTime - projectedTime
        // Commit the current corrected phase before starting a new PLL window;
        // otherwise a second sample would discard the portion already slewed.
        anchorPlaybackTime = projectedTime
        anchorHostTime = now
        correctionRate = 0
        correctionStartHostTime = nil
        correctionDuration = 0
        guard abs(correction) > 0.001 else { return }

        let maximumCorrectionRate = 0.08
        let duration = min(max(abs(correction) / maximumCorrectionRate, 0.5), 2.0)
        correctionRate = min(max(correction / duration, -maximumCorrectionRate), maximumCorrectionRate)
        correctionStartHostTime = now
        correctionDuration = duration
    }

    private func updateDisplayLinkState() {
        guard shouldRenderDanmaku, isPlaying, window != nil else {
            stopDisplayLink()
            return
        }
        refreshEnvironmentSnapshotIfNeeded()

        // Keep the compositor independent from this timer. The timer only
        // maintains the entry set; it should sleep when the next event is far
        // away and never run at 60 Hz just because playback is accelerated.
        let cadenceMilliseconds = lifecycleCadenceMilliseconds()
        if lifecycleTimer != nil,
           lifecycleTimerCadenceMilliseconds == cadenceMilliseconds {
            return
        }
        stopDisplayLink()

        // Scrolling entries are composited by Core Animation at the display's
        // native refresh rate. This timer only maintains the entry set. A
        // 30 Hz housekeeping pass is sufficient for normal playback, while a
        // 60 Hz pass prevents high-rate playback from batching several due
        // buckets into one main-thread callback.
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now(),
            repeating: .milliseconds(cadenceMilliseconds),
            leeway: .milliseconds(cadenceMilliseconds == 16 ? 2 : 8)
        )
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        lifecycleTimer = timer
        lifecycleTimerCadenceMilliseconds = cadenceMilliseconds
        timer.resume()
    }

    private func lifecycleCadenceMilliseconds() -> Int {
        if activeEntries.isEmpty {
            guard let nextSpawnTime = nextScheduledSpawnTime else { return 250 }
            let timeUntilNextSpawn = nextSpawnTime - effectivePlaybackTime()
            return timeUntilNextSpawn <= 0.75 ? 33 : 250
        }

        if activeEntries.values.contains(where: { $0.item.isScrolling }) {
            // Core Animation still composites scrolling entries at the normal
            // 60 Hz cadence. This pass only retires entries and spawns new
            // ones, so 30 Hz is sufficient unless accelerated playback is
            // about to cross another time bucket.
            if playbackRate > 1.15,
               let nextSpawnTime = nextScheduledSpawnTime,
               nextSpawnTime - effectivePlaybackTime() <= 0.5 {
                return 16
            }
            return 33
        }
        return 66
    }

    private var nextScheduledSpawnTime: TimeInterval? {
        var bucketIndex = nextBucketIndex
        var itemIndex = nextBucketItemIndex
        while bucketIndex < timeBuckets.count {
            let bucketItems = timeBuckets[bucketIndex].items
            if itemIndex < bucketItems.count {
                return bucketItems[itemIndex].time
            }
            bucketIndex += 1
            itemIndex = 0
        }
        return nil
    }

    private func stopDisplayLink() {
        lifecycleTimer?.setEventHandler {}
        lifecycleTimer?.cancel()
        lifecycleTimer = nil
        lifecycleTimerCadenceMilliseconds = nil
    }

    private func updateAnimationPauseState() {
        guard shouldRenderDanmaku else { return }
        // The rotation transition owns scrolling animations until its final
        // reconciliation pass. An intermediate SwiftUI update must not sample
        // a different playback time and move every active entry.
        if isLayoutTransitioning || rotationReconciliationPending {
            // A pause is still an explicit playback state change. Preserve the
            // current presentation frame, but do not let an old CA animation
            // continue while the video is paused during rotation.
            if !isPlaying,
               activeEntries.values.contains(where: {
                   $0.item.isScrolling
                       && $0.spriteLayer.animation(forKey: Self.scrollingAnimationKey) != nil
               }) {
                detachScrollingAnimations(at: effectivePlaybackTime())
            }
            return
        }
        guard window != nil else {
            detachScrollingAnimations(at: effectivePlaybackTime())
            return
        }
        let playbackTime = effectivePlaybackTime()
        if isPlaying {
            resumeScrollingAnimations(at: playbackTime)
        } else {
            detachScrollingAnimations(at: playbackTime)
        }
    }

    private func installScrollingAnimation(
        for entry: ActiveEntry,
        at playbackTime: TimeInterval,
        startingPosition: CGPoint? = nil
    ) {
        guard entry.item.isScrolling,
              isPlaying,
              !isLayoutTransitioning,
              !rotationReconciliationPending
        else { return }

        let band = displayBand()
        let currentPosition = startingPosition ?? position(for: entry, at: playbackTime, band: band)
        let trajectory = entry.scrollingTrajectory ?? ScrollingTrajectory(
            referenceTime: entry.item.time,
            duration: entry.duration,
            startX: scrollingStartX(
                containerWidth: band.width,
                labelWidth: entry.labelSize.width
            ),
            endX: scrollingEndX(
                containerWidth: band.width,
                labelWidth: entry.labelSize.width
            )
        )
        let endX = trajectory.endX
        let age = min(max(playbackTime - entry.item.time, 0), entry.duration)
        let remainingMediaDuration = max(entry.duration - age, 0.05)
        let animationDuration = remainingMediaDuration / max(playbackRate, 0.1)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        entry.spriteLayer.removeAnimation(forKey: Self.scrollingAnimationKey)
        entry.spriteLayer.position = CGPoint(x: endX, y: currentPosition.y)
        let animation = CABasicAnimation(keyPath: "position.x")
        animation.fromValue = currentPosition.x
        animation.toValue = endX
        animation.duration = animationDuration
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        // Keep the compositor on the normal 60 Hz cadence. The lifecycle
        // timer below is intentionally lower frequency, but it must never
        // become the source of the scrolling animation's frame rate.
        animation.preferredFrameRateRange = CAFrameRateRange(
            minimum: 60,
            maximum: 60,
            preferred: 60
        )
        animation.isRemovedOnCompletion = false
        animation.fillMode = .forwards
        entry.spriteLayer.add(animation, forKey: Self.scrollingAnimationKey)
        CATransaction.commit()
    }

    private func detachScrollingAnimations(at playbackTime: TimeInterval) {
        guard !activeEntries.isEmpty else { return }
        let band = displayBand()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for entry in activeEntries.values where entry.item.isScrolling {
            let fallbackPosition = position(for: entry, at: playbackTime, band: band)
            let presentationPosition = entry.spriteLayer.presentation()?.position ?? fallbackPosition
            entry.spriteLayer.removeAnimation(forKey: Self.scrollingAnimationKey)
            entry.spriteLayer.position = presentationPosition
        }
        CATransaction.commit()
    }

    private func resumeScrollingAnimations(at playbackTime: TimeInterval) {
        guard isPlaying,
              !isLayoutTransitioning,
              !rotationReconciliationPending
        else { return }

        for entry in activeEntries.values where entry.item.isScrolling {
            guard entry.spriteLayer.animation(forKey: Self.scrollingAnimationKey) == nil else { continue }
            let age = playbackTime - entry.item.time
            guard age >= 0, age < entry.duration else { continue }
            installScrollingAnimation(for: entry, at: playbackTime)
        }
    }

    private func scheduleRotationReconciliation() {
        guard rotationReconciliationPending,
              !rotationReconciliationScheduled
        else { return }

        rotationReconciliationScheduled = true
        let generation = rotationReconciliationGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.rotationReconciliationScheduled = false
            guard self.rotationReconciliationPending,
                  !self.isLayoutTransitioning,
                  self.rotationReconciliationGeneration == generation
            else { return }
            self.rotationReconciliationReady = true
            self.reconcileRotationLayoutIfNeeded()
            self.updateDisplayLinkState()
            self.updateAnimationPauseState()
        }
    }

    private func reconcileRotationLayoutIfNeeded() {
        guard rotationReconciliationPending,
              rotationReconciliationReady,
              !isLayoutTransitioning
        else { return }

        let size = bounds.size
        guard size.width > 1, size.height > 1 else { return }

        rotationReconciliationPending = false
        let needsContentReconciliation = needsContentReconciliationAfterTransition
        needsContentReconciliationAfterTransition = false

        // Normal playback continues while UIKit rotates the surface. Use the
        // current media time for expiration, but leave each scrolling entry's
        // captured CA trajectory intact. Reinstalling it against the final
        // bounds is the discontinuity that the player-integrated canvas avoids.
        let playbackTime = effectivePlaybackTime()
        rotationPlaybackTime = nil
        if shouldRenderDanmaku {
            if needsContentReconciliation {
                rebuildVisibleItems(at: playbackTime, animated: false)
            } else {
                // Anchored entries can adopt the final band immediately. The
                // scrolling entries keep their existing presentation path.
                updateActiveEntryFrames(at: playbackTime, updatesScrollingPositions: false)
            }
            resumeScrollingAnimations(at: playbackTime)
        } else {
            clearActiveLabels()
        }
        lastLayoutSize = size
    }

    private func rebuildVisibleItems(at playbackTime: TimeInterval, animated: Bool) {
        clearActiveLabels()
        guard shouldRenderDanmaku else { return }
        scrollingLaneStates.removeAll(keepingCapacity: true)

        let replayStart = playbackTime - maximumDisplayDuration()
        let startIndex = firstItemIndex(atOrAfter: replayStart)
        let endIndex = firstItemIndex(after: playbackTime)
        guard startIndex < endIndex else {
            setNextSpawnPosition(after: playbackTime)
            return
        }

        var visibleItems: [DanmakuItem] = []
        visibleItems.reserveCapacity(min(maxActiveCount, endIndex - startIndex))
        for item in items[startIndex..<endIndex] {
            let age = playbackTime - item.time
            guard age >= 0, age < displayDuration(for: item) else { continue }
            visibleItems.append(item)
            if visibleItems.count > maxActiveCount {
                visibleItems.removeFirst(visibleItems.count - maxActiveCount)
            }
        }

        let scale = window?.screen.scale ?? traitCollection.displayScale
        visibleItems.forEach { enqueueImagePrewarm(for: $0, scale: scale) }
        for item in visibleItems {
            switch spawn(item, at: playbackTime, animated: animated) {
            case .waitingForImage:
                enqueuePendingSpawn(item)
            case .spawned, .skipped:
                break
            }
        }
        setNextSpawnPosition(after: playbackTime)
    }

    private func spawnDueItems(at playbackTime: TimeInterval) {
        prewarmUpcomingImages(at: playbackTime)
        skipExpiredItems(at: playbackTime)
        var spawnedCount = 0
        let spawnLimit = maxSpawnPerTick
        let currentBucket = timeBucketIndex(for: playbackTime)
        while nextBucketIndex < timeBuckets.count,
              timeBuckets[nextBucketIndex].index <= currentBucket,
              spawnedCount < spawnLimit {
            let bucket = timeBuckets[nextBucketIndex]
            if isBucketTooStale(bucket.index, at: playbackTime) {
                advanceToNextBucket()
                continue
            }

            let bucketItems = bucket.items
            while nextBucketItemIndex < bucketItems.count, spawnedCount < spawnLimit {
                let item = bucketItems[nextBucketItemIndex]
                let age = playbackTime - item.time
                guard age >= -Self.timeBucketDuration, age < displayDuration(for: item) else {
                    nextBucketItemIndex += 1
                    continue
                }
                switch spawn(item, at: playbackTime, animated: true) {
                case .spawned:
                    nextBucketItemIndex += 1
                    spawnedCount += 1
                case .skipped:
                    nextBucketItemIndex += 1
                case .waitingForImage:
                    // Keep the item at the head of the queue. The background
                    // prewarm completion will make it eligible on the next
                    // housekeeping pass without synchronously rasterizing on
                    // the playback thread.
                    return
                }
            }

            if nextBucketItemIndex >= bucketItems.count {
                advanceToNextBucket()
            }
        }
    }

    private func skipExpiredItems(at playbackTime: TimeInterval) {
        let maximumDuration = maximumDisplayDuration()
        while nextBucketIndex < timeBuckets.count {
            let bucket = timeBuckets[nextBucketIndex]
            guard bucketEndTime(for: bucket.index) >= playbackTime - maximumDuration else {
                advanceToNextBucket()
                continue
            }

            while nextBucketItemIndex < bucket.items.count,
                  playbackTime - bucket.items[nextBucketItemIndex].time > maximumDuration {
                nextBucketItemIndex += 1
            }
            if nextBucketItemIndex >= bucket.items.count {
                advanceToNextBucket()
                continue
            }
            return
        }
    }

    private func spawn(_ item: DanmakuItem, at playbackTime: TimeInterval, animated _: Bool) -> SpawnResult {
        guard item.isSupported, bounds.width > 20, bounds.height > 20 else { return .skipped }
        guard canSpawnAdditionalItem else { return .skipped }

        let fontSize = fontSize(for: item)
        let font = UIFont.systemFont(ofSize: fontSize, weight: settings.fontWeight.uiFontWeight)
        let labelSize = labelSize(for: item, font: font)

        let duration = displayDuration(for: item)
        let band = displayBand()
        let laneHeight = max(labelSize.height, fontSize + 10)
        let laneCount = max(1, Int(max(1, band.height) / laneHeight))
        let id = item.id
        guard activeEntries[id] == nil else { return .skipped }
        guard let renderImage = renderImage(
            for: item,
            font: font,
            size: labelSize,
            // A mounted playing overlay must never rasterize on the main
            // thread. Tests and initial, not-yet-mounted views still need an
            // immediate image so their first layout is deterministic.
            allowSynchronousRender: !isPlaying || window == nil
        ) else {
            return .waitingForImage
        }

        // Reserve a lane only after the image is ready. A pending image may
        // be retried several times; reserving before that point would mutate
        // lane state on every retry and make fast streams bunch or jump.
        let lane: Int
        if item.isScrolling {
            guard let selectedLane = laneIndex(
                for: item,
                laneCount: laneCount,
                labelWidth: labelSize.width,
                at: item.time
            ) else {
                return .skipped
            }
            lane = selectedLane
        } else {
            lane = stableLane(for: item.id, laneCount: laneCount)
        }
        let y = yPosition(for: item, lane: lane, laneHeight: laneHeight, band: band, labelSize: labelSize)
        let normalizedLane = normalizedLanePosition(for: y, band: band, labelSize: labelSize)
        let spriteLayer = dequeueSpriteLayer()
        spriteLayer.contents = renderImage.image
        spriteLayer.contentsScale = renderImage.scale
        spriteLayer.bounds = CGRect(origin: .zero, size: labelSize)
        spriteLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        spriteLayer.opacity = 0
        layer.addSublayer(spriteLayer)
        let scrollingTrajectory = item.isScrolling
            ? ScrollingTrajectory(
                referenceTime: item.time,
                duration: duration,
                startX: scrollingStartX(
                    containerWidth: band.width,
                    labelWidth: labelSize.width
                ),
                endX: scrollingEndX(
                    containerWidth: band.width,
                    labelWidth: labelSize.width
                )
            )
            : nil
        activeEntries[id] = ActiveEntry(
            id: id,
            item: item,
            duration: duration,
            normalizedLane: normalizedLane,
            labelSize: labelSize,
            fontSize: fontSize,
            spriteLayer: spriteLayer,
            scrollingTrajectory: scrollingTrajectory
        )
        renderPlaybackTime = playbackTime
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let entry = activeEntries[id] {
            spriteLayer.position = position(for: entry, at: playbackTime, band: band)
            spriteLayer.opacity = entryOpacity(
                item: item,
                age: playbackTime - item.time,
                duration: duration
            )
        }
        CATransaction.commit()

        if let entry = activeEntries[id], entry.item.isScrolling {
            installScrollingAnimation(for: entry, at: playbackTime)
        }
        return .spawned
    }

    /// Rasterize each entry once when it enters the active set. The display
    /// link then only composites cached glyph images, which keeps text layout
    /// and shadow generation off the 60 Hz path while preserving one shared
    /// render surface and a media-time-driven position.
    private func renderImage(
        for item: DanmakuItem,
        font: UIFont,
        size: CGSize,
        allowSynchronousRender: Bool
    ) -> CachedRenderImage? {
        let scale = window?.screen.scale ?? traitCollection.displayScale
        let request = renderImageRequest(for: item, font: font, size: size, scale: scale)
        let key = request.key
        if let cached = renderImageCache[key] {
            return cached
        }

        guard allowSynchronousRender else { return nil }

        let image = RenderImageFactory.make(request)
        guard let cgImage = image.cgImage else { return nil }
        insertCachedRenderImage(
            CachedRenderImage(image: cgImage, scale: image.scale),
            for: key
        )
        trimRenderImageCacheIfNeeded()
        return renderImageCache[key]
    }

    private func labelSize(for item: DanmakuItem, font: UIFont) -> CGSize {
        let textSize = measuredTextSize(for: item, font: font)
        return CGSize(
            width: min(max(textSize.width + 18, 44), bounds.width * 1.45),
            height: max(textSize.height + 8, font.pointSize + 8)
        )
    }

    private func renderImageRequest(
        for item: DanmakuItem,
        font: UIFont,
        size: CGSize,
        scale: CGFloat
    ) -> RenderImageRequest {
        RenderImageRequest(
            key: RenderImageKey(
                text: item.text,
                fontSizeTenths: Int((font.pointSize * 10).rounded()),
                fontWeight: settings.fontWeight,
                color: item.color,
                opacityThousandths: Int((settings.opacity * 1_000).rounded()),
                widthPixels: Int((size.width * scale).rounded()),
                heightPixels: Int((size.height * scale).rounded()),
                scaleTenths: Int((scale * 10).rounded())
            ),
            text: item.text,
            fontSize: font.pointSize,
            fontWeight: settings.fontWeight,
            color: item.color,
            opacity: settings.opacity,
            size: size,
            scale: scale
        )
    }

    /// Rasterize a small look-ahead window off the main thread. The layer
    /// itself is still created on the main thread, but the expensive glyph
    /// drawing and shadow generation is completed before the item becomes
    /// due. Playing items wait for this cache instead of rasterizing on the
    /// playback thread.
    private func prewarmUpcomingImages(at playbackTime: TimeInterval) {
        guard shouldRenderDanmaku, isPlaying, window != nil, bounds.width > 20, bounds.height > 20 else { return }
        let lookahead: TimeInterval = isLoadShedding ? 0.55 : 0.8
        guard let nextSpawnTime = nextScheduledSpawnTime,
              nextSpawnTime - playbackTime <= lookahead
        else { return }

        let prewarmBucket = Int((max(0, playbackTime) / 0.25).rounded(.down))
        guard lastPrewarmTimeBucket != prewarmBucket else { return }
        lastPrewarmTimeBucket = prewarmBucket
        let startIndex = firstItemIndex(atOrAfter: max(0, playbackTime))
        let lookaheadEndIndex = firstItemIndex(atOrAfter: playbackTime + lookahead)
        let maxItems = min(8, max(1, maxSpawnPerTick * 2))
        let endIndex = min(items.count, min(lookaheadEndIndex, startIndex + maxItems))
        guard startIndex < endIndex else { return }

        let scale = window?.screen.scale ?? traitCollection.displayScale
        for item in items[startIndex..<endIndex] {
            enqueueImagePrewarm(for: item, scale: scale)
        }
    }

    private func enqueueImagePrewarm(for item: DanmakuItem, scale: CGFloat) {
        guard item.isSupported, isPlaying, window != nil else { return }
        let fontSize = fontSize(for: item)
        let font = UIFont.systemFont(ofSize: fontSize, weight: settings.fontWeight.uiFontWeight)
        let size = labelSize(for: item, font: font)
        let request = renderImageRequest(for: item, font: font, size: size, scale: scale)
        let key = request.key
        guard pendingRenderImageKeys.count < 12 else { return }
        guard renderImageCache[key] == nil,
              pendingRenderImageKeys.insert(key).inserted
        else { return }

        let token = PrewarmCancellationToken()
        prewarmTokens[key] = token
        renderImagePrewarmQueue.async { [weak self, token] in
            guard !token.isCancelled else { return }
            let image = RenderImageFactory.make(request)
            guard !token.isCancelled else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.prewarmTokens[key] === token else { return }
                self.prewarmTokens[key] = nil
                self.pendingRenderImageKeys.remove(key)
                guard !token.isCancelled,
                      self.window != nil,
                      self.shouldRenderDanmaku,
                      self.renderImageCache[key] == nil
                else { return }
                guard let cgImage = image.cgImage else { return }
                self.insertCachedRenderImage(
                    CachedRenderImage(image: cgImage, scale: image.scale),
                    for: key
                )
                self.trimRenderImageCacheIfNeeded()
                self.schedulePendingSpawnRetry()
            }
        }
    }

    private func cancelPendingPrewarm() {
        prewarmTokens.values.forEach { $0.cancel() }
        prewarmTokens.removeAll(keepingCapacity: true)
        pendingRenderImageKeys.removeAll(keepingCapacity: true)
        lastPrewarmTimeBucket = nil
    }

    private func schedulePendingSpawnRetry() {
        guard isPlaying, !pendingSpawnRetryScheduled else { return }
        pendingSpawnRetryScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingSpawnRetryScheduled = false
            guard self.isPlaying, self.window != nil, self.shouldRenderDanmaku else { return }
            self.retryPendingSpawns(at: self.effectivePlaybackTime())
            self.updateDisplayLinkState()
        }
    }

    private func enqueuePendingSpawn(_ item: DanmakuItem) {
        guard pendingSpawnIDs.insert(item.id).inserted else { return }
        let pendingLimit = max(8, maxActiveCount * 2)
        if pendingSpawnItems.count >= pendingLimit,
           let droppedItem = pendingSpawnItems.first {
            pendingSpawnItems.removeFirst()
            pendingSpawnIDs.remove(droppedItem.id)
        }
        pendingSpawnItems.append(item)
    }

    private func retryPendingSpawns(at playbackTime: TimeInterval) {
        guard !pendingSpawnItems.isEmpty, shouldRenderDanmaku else { return }

        var remainingItems: [DanmakuItem] = []
        remainingItems.reserveCapacity(pendingSpawnItems.count)
        for item in pendingSpawnItems {
            let age = playbackTime - item.time
            guard age >= -Self.timeBucketDuration,
                  age < displayDuration(for: item)
            else {
                pendingSpawnIDs.remove(item.id)
                continue
            }

            switch spawn(item, at: playbackTime, animated: isPlaying) {
            case .waitingForImage:
                remainingItems.append(item)
            case .spawned, .skipped:
                pendingSpawnIDs.remove(item.id)
            }
        }
        pendingSpawnItems = remainingItems
    }

    private func trimRenderImageCacheIfNeeded() {
        while renderImageCacheCost > Self.renderImageCachePixelBudget,
              let oldestKey = renderImageCacheOrder.first {
            renderImageCacheOrder.removeFirst()
            if let removed = renderImageCache.removeValue(forKey: oldestKey) {
                renderImageCacheCost = max(0, renderImageCacheCost - removed.pixelCost)
            }
        }
    }

    private func insertCachedRenderImage(_ image: CachedRenderImage, for key: RenderImageKey) {
        if let previous = renderImageCache.updateValue(image, forKey: key) {
            renderImageCacheCost = max(0, renderImageCacheCost - previous.pixelCost)
        } else {
            renderImageCacheOrder.append(key)
        }
        renderImageCacheCost += image.pixelCost
    }

    private func updateActiveEntryFrames(
        at playbackTime: TimeInterval,
        updatesScrollingPositions: Bool = false
    ) {
        renderPlaybackTime = playbackTime
        guard !activeEntries.isEmpty else {
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        var retiredIDs: [String] = []
        retiredIDs.reserveCapacity(2)
        let band = displayBand()
        for entry in activeEntries.values {
            if shouldRetire(entry: entry, at: playbackTime) {
                retiredIDs.append(entry.id)
                continue
            }

            let age = playbackTime - entry.item.time
            guard age >= 0, age < entry.duration else {
                entry.spriteLayer.opacity = 0
                continue
            }
            // Scrolling entries are already moved by Core Animation. During a
            // normal playback maintenance tick, only their lifetime/opacity
            // is checked; resolving their geometry or querying animation state
            // here would put needless work back on the main thread. A layout
            // or seek explicitly opts into one geometry reconciliation pass.
            // A scrolling entry is normally owned by its CA animation. Changing
            // the model position while that animation is attached rebases the
            // layer and produces a visible hop, especially during rotation.
            // Only reconcile it when it is already paused/detached.
            if !entry.item.isScrolling
                || (updatesScrollingPositions
                    && entry.spriteLayer.animation(forKey: Self.scrollingAnimationKey) == nil) {
                let nextPosition = position(for: entry, at: playbackTime, band: band)
                if entry.spriteLayer.position != nextPosition {
                    entry.spriteLayer.position = nextPosition
                }
            }
            if entry.item.isScrolling {
                if entry.spriteLayer.opacity != 1 {
                    entry.spriteLayer.opacity = 1
                }
            } else {
                let nextOpacity = entryOpacity(
                    item: entry.item,
                    age: age,
                    duration: entry.duration
                )
                if abs(entry.spriteLayer.opacity - nextOpacity) > 0.001 {
                    entry.spriteLayer.opacity = nextOpacity
                }
            }
        }
        for id in retiredIDs {
            if let spriteLayer = activeEntries[id]?.spriteLayer {
                recycleSpriteLayer(spriteLayer)
            }
            activeEntries[id] = nil
        }
    }

    private func position(
        for entry: ActiveEntry,
        at playbackTime: TimeInterval,
        band: CGRect
    ) -> CGPoint {
        let y = yPosition(
            for: entry.normalizedLane,
            band: band,
            labelSize: entry.labelSize
        )
        guard entry.item.isScrolling else {
            return CGPoint(x: activeGeometryBounds.midX, y: y)
        }
        let trajectory = entry.scrollingTrajectory ?? ScrollingTrajectory(
            referenceTime: entry.item.time,
            duration: entry.duration,
            startX: scrollingStartX(
                containerWidth: band.width,
                labelWidth: entry.labelSize.width
            ),
            endX: scrollingEndX(
                containerWidth: band.width,
                labelWidth: entry.labelSize.width
            )
        )
        let progress = trajectory.progress(at: playbackTime)
        let x = trajectory.startX + (trajectory.endX - trajectory.startX) * progress
        return CGPoint(x: x, y: y)
    }

    private func entryOpacity(
        item: DanmakuItem,
        age: TimeInterval,
        duration: TimeInterval
    ) -> Float {
        guard !item.isScrolling else {
            return 1
        }
        let progress = min(max(age / max(duration, 0.01), 0), 1)
        let opacity: Float
        if progress < 0.06 {
            opacity = Float(progress / 0.06)
        } else if progress > 0.92 {
            opacity = Float((1 - progress) / 0.08)
        } else {
            opacity = 1
        }
        return max(0, min(1, opacity))
    }

    private func clearActiveLabels() {
        for entry in activeEntries.values {
            recycleSpriteLayer(entry.spriteLayer)
        }
        activeEntries.removeAll(keepingCapacity: true)
        pendingSpawnItems.removeAll(keepingCapacity: true)
        pendingSpawnIDs.removeAll(keepingCapacity: true)
    }

    private func dequeueSpriteLayer() -> CALayer {
        let spriteLayer = recycledSpriteLayers.popLast() ?? CALayer()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        spriteLayer.removeAllAnimations()
        spriteLayer.removeFromSuperlayer()
        spriteLayer.contents = nil
        spriteLayer.opacity = 0
        CATransaction.commit()
        return spriteLayer
    }

    private func recycleSpriteLayer(_ spriteLayer: CALayer) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        spriteLayer.removeAllAnimations()
        spriteLayer.removeFromSuperlayer()
        spriteLayer.contents = nil
        spriteLayer.opacity = 0
        CATransaction.commit()
        guard recycledSpriteLayers.count < 64 else { return }
        recycledSpriteLayers.append(spriteLayer)
    }

    private func shouldRetire(
        entry: ActiveEntry,
        at playbackTime: TimeInterval
    ) -> Bool {
        let duration = entry.duration
        let age = playbackTime - entry.item.time
        guard age >= 0 else { return false }
        if age >= duration - (entry.item.isScrolling ? 0 : 0.04) {
            return true
        }
        return false
    }

    private func scrollingStartX(
        containerWidth: CGFloat,
        labelWidth: CGFloat
    ) -> CGFloat {
        containerWidth + labelWidth / 2
    }

    private func scrollingEndX(
        containerWidth: CGFloat,
        labelWidth: CGFloat
    ) -> CGFloat {
        -labelWidth / 2 - scrollingRetirementOverscan(for: containerWidth)
    }

    private func scrollingTravelDistance(labelWidth: CGFloat) -> CGFloat {
        max(
            scrollingStartX(
                containerWidth: activeGeometryBounds.width,
                labelWidth: labelWidth
            )
                - scrollingEndX(
                    containerWidth: activeGeometryBounds.width,
                    labelWidth: labelWidth
                ),
            1
        )
    }

    private func scrollingRetirementOverscan(for containerWidth: CGFloat) -> CGFloat {
        min(max(containerWidth * 0.035, 8), 28)
    }

    private var canSpawnAdditionalItem: Bool {
        activeEntries.count < maxActiveCount
    }

    private var activeGeometryBounds: CGRect {
        bounds
    }

    private func measuredTextSize(for item: DanmakuItem, font: UIFont) -> CGSize {
        let key = TextMeasurementKey(
            text: item.text,
            fontSizeTenths: Int((font.pointSize * 10).rounded()),
            fontWeight: settings.fontWeight
        )
        if let cached = textSizeCache[key] {
            return cached
        }

        let size = (item.text as NSString).size(withAttributes: [.font: font])
        let measured = CGSize(width: ceil(size.width), height: ceil(max(size.height, font.lineHeight)))
        textSizeCache[key] = measured
        textSizeCacheOrder.append(key)
        trimTextSizeCacheIfNeeded()
        return measured
    }

    private func trimTextSizeCacheIfNeeded() {
        guard textSizeCacheOrder.count > 520 else { return }
        let overflow = textSizeCacheOrder.count - 420
        let removedKeys = textSizeCacheOrder.prefix(overflow)
        removedKeys.forEach { textSizeCache[$0] = nil }
        textSizeCacheOrder.removeFirst(overflow)
    }

    private func displayBand() -> CGRect {
        let geometry = activeGeometryBounds
        let usableMinY = max(0, topInset)
        let usableMaxY = max(usableMinY + 1, geometry.height - max(0, bottomInset))
        let usableHeight = max(1, usableMaxY - usableMinY)
        let fraction: CGFloat
        switch settings.displayArea {
        case .topQuarter:
            fraction = 0.25
        case .topHalf:
            fraction = 0.5
        case .topThreeQuarters:
            fraction = 0.75
        case .center:
            fraction = 0.5
        case .full:
            fraction = 1
        }
        let targetHeight = geometry.height * fraction
        let minimumHeight = minimumDisplayBandHeight(for: fraction, usableHeight: usableHeight)
        let height = min(usableHeight, max(targetHeight, minimumHeight))
        return CGRect(x: 0, y: usableMinY, width: geometry.width, height: height)
    }

    private func minimumDisplayBandHeight(for fraction: CGFloat, usableHeight: CGFloat) -> CGFloat {
        guard fraction < 1 else { return usableHeight }
        let geometry = activeGeometryBounds
        let compactScale: CGFloat = 0.70
        let representativeFontSize = min(
            max(25 * compactScale * CGFloat(settings.fontScale), 11.7),
            18 * 1.35
        )
        let laneHeight = representativeFontSize + 10
        let preferredLaneCount: CGFloat
        if geometry.height < 220 {
            preferredLaneCount = fraction <= 0.25 ? 3 : 4
        } else {
            preferredLaneCount = fraction <= 0.25 ? 4 : 5
        }
        return min(usableHeight, laneHeight * preferredLaneCount)
    }

    private func normalizedLanePosition(
        for y: CGFloat,
        band: CGRect,
        labelSize: CGSize
    ) -> CGFloat {
        let minimumY = band.minY + labelSize.height / 2
        let maximumY = band.maxY - labelSize.height / 2
        guard maximumY > minimumY else { return 0.5 }
        return min(max((y - minimumY) / (maximumY - minimumY), 0), 1)
    }

    private func yPosition(
        for normalizedLane: CGFloat,
        band: CGRect,
        labelSize: CGSize
    ) -> CGFloat {
        let minimumY = band.minY + labelSize.height / 2
        let maximumY = band.maxY - labelSize.height / 2
        guard maximumY > minimumY else { return band.midY }
        let y = minimumY + min(max(normalizedLane, 0), 1) * (maximumY - minimumY)
        let geometry = activeGeometryBounds
        return min(max(y, labelSize.height / 2), geometry.height - labelSize.height / 2)
    }

    private func yPosition(
        for item: DanmakuItem,
        lane: Int,
        laneHeight: CGFloat,
        band: CGRect,
        labelSize: CGSize
    ) -> CGFloat {
        if item.isBottomAnchored {
            let anchoredLaneCount = min(3, max(1, Int(max(1, band.height) / laneHeight)))
            let anchoredLane = stableLane(for: item.id, laneCount: anchoredLaneCount)
            let y = band.maxY - laneHeight * (CGFloat(anchoredLane) + 0.5)
            let geometry = activeGeometryBounds
            return min(max(y, labelSize.height / 2), geometry.height - labelSize.height / 2)
        }
        if item.isTopAnchored {
            let anchoredLaneCount = min(3, max(1, Int(max(1, band.height) / laneHeight)))
            let anchoredLane = stableLane(for: item.id, laneCount: anchoredLaneCount)
            let y = band.minY + laneHeight * (CGFloat(anchoredLane) + 0.5)
            let geometry = activeGeometryBounds
            return min(max(y, labelSize.height / 2), geometry.height - labelSize.height / 2)
        }
        let y = band.minY + laneHeight * (CGFloat(lane) + 0.5)
        let geometry = activeGeometryBounds
        return min(max(y, labelSize.height / 2), geometry.height - labelSize.height / 2)
    }

    private func laneIndex(
        for item: DanmakuItem,
        laneCount: Int,
        labelWidth: CGFloat,
        at itemTime: TimeInterval
    ) -> Int? {
        guard laneCount > 1, item.isScrolling else { return 0 }
        let startLane = stableLane(for: item.id, laneCount: laneCount)
        for offset in 0..<laneCount {
            let lane = (startLane + offset) % laneCount
            if (scrollingLaneStates[lane]?.releaseTime ?? 0) <= itemTime {
                scrollingLaneStates[lane] = LaneState(
                    releaseTime: itemTime + laneEntranceDelay(for: labelWidth),
                    itemWidth: labelWidth
                )
                return lane
            }
        }

        guard let earliest = scrollingLaneStates.min(by: { lhs, rhs in
            lhs.value.releaseTime < rhs.value.releaseTime
        }) else {
            return startLane
        }
        guard earliest.value.releaseTime - itemTime <= maxLaneOverlapTolerance else {
            return nil
        }
        scrollingLaneStates[earliest.key] = LaneState(
            releaseTime: itemTime + laneEntranceDelay(for: labelWidth),
            itemWidth: labelWidth
        )
        return earliest.key
    }

    private func laneEntranceDelay(for labelWidth: CGFloat) -> TimeInterval {
        let width = activeGeometryBounds.width
        let gap = width > 640 ? 40.0 : 30.0
        let travelDistance = max(width + labelWidth, 1)
        let protectedWidth = min(labelWidth + gap, width * 0.72)
        return scrollDuration * TimeInterval(protectedWidth / travelDistance)
    }

    private var maxLaneOverlapTolerance: TimeInterval {
        activeGeometryBounds.width > 640 ? 0.16 : 0.10
    }

    private func displayDuration(for item: DanmakuItem) -> TimeInterval {
        item.isScrolling ? scrollDuration : 4.2
    }

    private func maximumDisplayDuration() -> TimeInterval {
        max(scrollDuration, 4.2)
    }

    private var scrollDuration: TimeInterval {
        // Keep the timeline independent of the surface width. Changing this
        // value at the 640pt portrait/landscape threshold would make every
        // active scrolling entry jump when the video rotates.
        7.2
    }

    private var maxActiveCount: Int {
        let baseCount = activeGeometryBounds.width > 640 ? 44 : 24
        return max(isLoadShedding ? 5 : 8, Int(Double(baseCount) * adaptiveDanmakuLoadFactor))
    }

    private var maxSpawnPerTick: Int {
        if isLayoutTransitioning || rotationReconciliationPending {
            // Keep text rasterization incremental while UIKit is committing
            // geometry. This prevents a completion-frame burst when several
            // bucketed items became due during the transition.
            return 1
        }
        let baseCount = activeGeometryBounds.width > 640 ? 6 : 4
        return max(1, Int(Double(baseCount) * adaptiveDanmakuLoadFactor))
    }

    private var adaptiveDanmakuLoadFactor: Double {
        let environment = currentPlaybackEnvironment
        let loadSheddingFactor = isLoadShedding ? 0.46 : 1.0
        if environment.isThermallyConstrained || environment.isLowPowerModeEnabled {
            return min(settings.loadFactor, 0.50) * loadSheddingFactor
        }
        if environment.isThermallyElevated {
            return min(settings.loadFactor, 0.66) * loadSheddingFactor
        }
        if environment.shouldPreferConservativePlayback {
            return min(settings.loadFactor, 0.72) * loadSheddingFactor
        }
        return settings.loadFactor * loadSheddingFactor
    }

    private static let timeBucketDuration: TimeInterval = 0.1

    private func fontSize(for item: DanmakuItem) -> CGFloat {
        // Keep the text metrics in media space. Rotation changes the available
        // track geometry, not the physical size of an already-rendered glyph.
        let compactScale: CGFloat = 0.70
        let maximumSize: CGFloat = 18
        let minimumSize: CGFloat = 13
        let scaledSize = CGFloat(item.fontSize) * compactScale * CGFloat(settings.fontScale)
        return min(max(scaledSize, minimumSize * 0.9), maximumSize * 1.35)
    }

    private func rebuildTimeBuckets() {
        timeBuckets.removeAll(keepingCapacity: true)
        timeBuckets.reserveCapacity(min(items.count, 600))
        for item in items {
            let bucketIndex = timeBucketIndex(for: item.time)
            if let lastIndex = timeBuckets.indices.last,
               timeBuckets[lastIndex].index == bucketIndex {
                timeBuckets[lastIndex].items.append(item)
            } else {
                timeBuckets.append(TimeBucket(index: bucketIndex, items: [item]))
            }
        }
        nextBucketIndex = 0
        nextBucketItemIndex = 0
    }

    private func setNextSpawnPosition(after playbackTime: TimeInterval) {
        guard !timeBuckets.isEmpty else {
            nextBucketIndex = 0
            nextBucketItemIndex = 0
            return
        }

        let nextItemIndex = firstItemIndex(after: playbackTime)
        guard nextItemIndex < items.count else {
            nextBucketIndex = timeBuckets.count
            nextBucketItemIndex = 0
            return
        }

        let bucketIndex = timeBucketIndex(for: items[nextItemIndex].time)
        nextBucketIndex = firstTimeBucketIndex(atOrAfter: bucketIndex)
        guard nextBucketIndex < timeBuckets.count else {
            nextBucketItemIndex = 0
            return
        }

        let bucketItems = timeBuckets[nextBucketIndex].items
        nextBucketItemIndex = bucketItems.firstIndex { $0.time > playbackTime } ?? bucketItems.count
        if nextBucketItemIndex >= bucketItems.count {
            advanceToNextBucket()
        }
    }

    private func advanceToNextBucket() {
        nextBucketIndex += 1
        nextBucketItemIndex = 0
    }

    private func isBucketTooStale(_ bucketIndex: Int, at playbackTime: TimeInterval) -> Bool {
        guard isLoadShedding || currentPlaybackEnvironment.isThermallyElevated else {
            // Normal and high-rate playback keep the bucket debt. Individual
            // expired items are removed by skipExpiredItems, but a late main
            // thread callback must not discard a whole time bucket.
            return false
        }
        return playbackTime - bucketEndTime(for: bucketIndex) > maximumBucketSpawnDelay
    }

    private var maximumBucketSpawnDelay: TimeInterval {
        if isLoadShedding {
            return 0.22
        }
        if currentPlaybackEnvironment.isThermallyElevated {
            return 0.32
        }
        return 0.48
    }

    private var currentPlaybackEnvironment: PlaybackEnvironment {
        let now = CACurrentMediaTime()
        if now - environmentSnapshotHostTime >= Self.environmentRefreshInterval {
            environmentSnapshot = PlaybackEnvironment.current
            environmentSnapshotHostTime = now
        }
        return environmentSnapshot
    }

    private func refreshEnvironmentSnapshotIfNeeded() {
        _ = currentPlaybackEnvironment
    }

    private func timeBucketIndex(for time: TimeInterval) -> Int {
        Int((max(0, time) / Self.timeBucketDuration).rounded(.down))
    }

    private func bucketEndTime(for bucketIndex: Int) -> TimeInterval {
        TimeInterval(bucketIndex + 1) * Self.timeBucketDuration
    }

    private func firstTimeBucketIndex(atOrAfter bucketIndex: Int) -> Int {
        var lower = 0
        var upper = timeBuckets.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if timeBuckets[middle].index < bucketIndex {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private func firstItemIndex(atOrAfter time: TimeInterval) -> Int {
        var lower = 0
        var upper = items.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if items[middle].time < time {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private func firstItemIndex(after time: TimeInterval) -> Int {
        var lower = 0
        var upper = items.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if items[middle].time <= time {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private func stableLane(for id: String, laneCount: Int) -> Int {
        guard laneCount > 1 else { return 0 }
        var hash: UInt64 = 5_381
        for scalar in id.unicodeScalars {
            hash = ((hash << 5) &+ hash) &+ UInt64(scalar.value)
        }
        return Int(hash % UInt64(laneCount))
    }

}

private extension UIColor {
    nonisolated static func danmakuRGB(_ rgb: UInt32) -> UIColor {
        let red = CGFloat((rgb >> 16) & 0xFF) / 255
        let green = CGFloat((rgb >> 8) & 0xFF) / 255
        let blue = CGFloat(rgb & 0xFF) / 255
        return UIColor(red: red, green: green, blue: blue, alpha: 1)
    }
}

private extension DanmakuFontWeightOption {
    nonisolated var uiFontWeight: UIFont.Weight {
        switch self {
        case .light:
            return .light
        case .regular:
            return .regular
        case .medium:
            return .medium
        case .semibold:
            return .semibold
        case .bold:
            return .bold
        case .heavy:
            return .heavy
        case .black:
            return .black
        }
    }
}
