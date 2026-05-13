import SwiftUI
import UIKit

struct DanmakuOverlayView: UIViewRepresentable {
    let items: [DanmakuItem]
    let currentTime: TimeInterval
    let isPlaying: Bool
    let playbackRate: Double
    let isEnabled: Bool
    let hasPresentedPlayback: Bool
    let settings: DanmakuSettings
    let topInset: CGFloat
    let bottomInset: CGFloat

    func makeUIView(context _: Context) -> DanmakuAnimationOverlayView {
        let view = DanmakuAnimationOverlayView()
        view.apply(
            items: items,
            currentTime: currentTime,
            isPlaying: isPlaying,
            playbackRate: playbackRate,
            isEnabled: isEnabled,
            hasPresentedPlayback: hasPresentedPlayback,
            settings: settings,
            topInset: topInset,
            bottomInset: bottomInset
        )
        return view
    }

    func updateUIView(_ uiView: DanmakuAnimationOverlayView, context _: Context) {
        uiView.apply(
            items: items,
            currentTime: currentTime,
            isPlaying: isPlaying,
            playbackRate: playbackRate,
            isEnabled: isEnabled,
            hasPresentedPlayback: hasPresentedPlayback,
            settings: settings,
            topInset: topInset,
            bottomInset: bottomInset
        )
    }

    static func dismantleUIView(_ uiView: DanmakuAnimationOverlayView, coordinator _: ()) {
        uiView.stop()
    }
}

final class DanmakuAnimationOverlayView: UIView {
    private struct ActiveEntry {
        let id: String
        let label: UILabel
        let completion: DanmakuAnimationCompletionDelegate?
        let createdAt: CFTimeInterval
    }

    private var items: [DanmakuItem] = []
    private var settings: DanmakuSettings = .default
    private var currentTime: TimeInterval = 0
    private var isPlaying = false
    private var playbackRate: Double = 1
    private var isEnabled = true
    private var hasPresentedPlayback = false
    private var topInset: CGFloat = 0
    private var bottomInset: CGFloat = 0
    private var nextItemIndex = 0
    private var anchorPlaybackTime: TimeInterval = 0
    private var anchorHostTime = CACurrentMediaTime()
    private var displayLink: CADisplayLink?
    private var activeEntries: [String: ActiveEntry] = [:]
    private var reusableLabels: [UILabel] = []
    private var laneReleaseTimes: [Int: TimeInterval] = [:]
    private var lastLayoutSize: CGSize = .zero
    private var animationsArePaused = false
    private var lastItemsSignature = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    deinit {
        displayLink?.invalidate()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = bounds.size
        guard size.width > 1, size.height > 1 else { return }
        guard abs(size.width - lastLayoutSize.width) > 1 || abs(size.height - lastLayoutSize.height) > 1 else { return }
        lastLayoutSize = size
        guard shouldRenderDanmaku else {
            clearActiveLabels()
            return
        }
        rebuildVisibleItems(at: effectivePlaybackTime(), animated: isPlaying)
        updateDisplayLinkState()
        updateAnimationPauseState()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateDisplayLinkState()
        updateAnimationPauseState()
    }

    func apply(
        items newItems: [DanmakuItem],
        currentTime newCurrentTime: TimeInterval,
        isPlaying newIsPlaying: Bool,
        playbackRate newPlaybackRate: Double,
        isEnabled newIsEnabled: Bool,
        hasPresentedPlayback newHasPresentedPlayback: Bool,
        settings newSettings: DanmakuSettings,
        topInset newTopInset: CGFloat,
        bottomInset newBottomInset: CGFloat
    ) {
        let normalizedRate = max(newPlaybackRate, 0.1)
        let sanitizedTime = max(0, newCurrentTime)
        let previousEffectiveTime = effectivePlaybackTime()
        let previousShouldRender = shouldRenderDanmaku
        let previousIsPlaying = isPlaying
        let itemsSignature = Self.signature(for: newItems)
        let didChangeItems = itemsSignature != lastItemsSignature
        let didChangeSettings = newSettings.normalized != settings
        let didChangeInsets = abs(newTopInset - topInset) > 0.5 || abs(newBottomInset - bottomInset) > 0.5
        let didChangeRate = abs(normalizedRate - playbackRate) > 0.05

        items = newItems
        lastItemsSignature = itemsSignature
        currentTime = sanitizedTime
        isPlaying = newIsPlaying
        playbackRate = normalizedRate
        isEnabled = newIsEnabled
        hasPresentedPlayback = newHasPresentedPlayback
        settings = newSettings.normalized
        topInset = max(0, newTopInset)
        bottomInset = max(0, newBottomInset)

        let currentShouldRender = shouldRenderDanmaku
        if !currentShouldRender {
            clearActiveLabels()
            nextItemIndex = firstItemIndex(after: sanitizedTime)
            syncPlaybackAnchor(to: sanitizedTime)
            stopDisplayLink()
            updateAnimationPauseState()
            return
        }

        if !previousShouldRender || didChangeItems || didChangeSettings || didChangeInsets || didChangeRate {
            syncPlaybackAnchor(to: sanitizedTime)
            rebuildVisibleItems(at: sanitizedTime, animated: newIsPlaying)
            updateDisplayLinkState()
            updateAnimationPauseState()
            return
        }

        let jumped = abs(sanitizedTime - previousEffectiveTime) > seekJumpThreshold || sanitizedTime + 0.2 < previousEffectiveTime
        syncPlaybackAnchor(to: sanitizedTime)

        if jumped || (previousIsPlaying != newIsPlaying && !newIsPlaying) {
            if jumped {
                rebuildVisibleItems(at: sanitizedTime, animated: newIsPlaying)
            }
        } else if previousIsPlaying != newIsPlaying && newIsPlaying {
            rebuildVisibleItems(at: sanitizedTime, animated: true)
        }

        updateDisplayLinkState()
        updateAnimationPauseState()
    }

    func stop() {
        stopDisplayLink()
        clearActiveLabels()
    }

    @objc private func tick(_ displayLink: CADisplayLink) {
        guard shouldRenderDanmaku, isPlaying else { return }
        spawnDueItems(at: effectivePlaybackTime(hostTime: displayLink.timestamp))
    }

    private func configureView() {
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = true
        isUserInteractionEnabled = false
        layer.allowsGroupOpacity = false
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
        return max(0, anchorPlaybackTime + elapsed * playbackRate)
    }

    private func syncPlaybackAnchor(to playbackTime: TimeInterval) {
        anchorPlaybackTime = max(0, playbackTime)
        anchorHostTime = CACurrentMediaTime()
    }

    private func updateDisplayLinkState() {
        guard shouldRenderDanmaku, isPlaying, window != nil else {
            stopDisplayLink()
            return
        }
        if displayLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 30, preferred: 30)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        displayLink?.isPaused = false
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func updateAnimationPauseState() {
        let shouldPause = !isPlaying || !shouldRenderDanmaku || window == nil
        guard shouldPause != animationsArePaused else { return }
        animationsArePaused = shouldPause
        if shouldPause {
            pauseLayerAnimations()
        } else {
            resumeLayerAnimations()
        }
    }

    private func pauseLayerAnimations() {
        guard layer.speed != 0 else { return }
        let pausedTime = layer.convertTime(CACurrentMediaTime(), from: nil)
        layer.speed = 0
        layer.timeOffset = pausedTime
    }

    private func resumeLayerAnimations() {
        guard layer.speed == 0 else { return }
        let pausedTime = layer.timeOffset
        layer.speed = 1
        layer.timeOffset = 0
        layer.beginTime = 0
        let timeSincePause = layer.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
        layer.beginTime = timeSincePause
    }

    private func rebuildVisibleItems(at playbackTime: TimeInterval, animated: Bool) {
        clearActiveLabels()
        guard shouldRenderDanmaku else { return }
        laneReleaseTimes.removeAll(keepingCapacity: true)

        let replayStart = playbackTime - maximumDisplayDuration()
        let startIndex = firstItemIndex(atOrAfter: replayStart)
        let endIndex = firstItemIndex(after: playbackTime)
        guard startIndex < endIndex else {
            nextItemIndex = endIndex
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

        for item in visibleItems {
            spawn(item, at: playbackTime, animated: animated)
        }
        nextItemIndex = endIndex
    }

    private func spawnDueItems(at playbackTime: TimeInterval) {
        skipExpiredItems(at: playbackTime)
        var spawnedCount = 0
        let spawnLimit = maxSpawnPerTick
        while nextItemIndex < items.count,
              items[nextItemIndex].time <= playbackTime,
              spawnedCount < spawnLimit {
            let item = items[nextItemIndex]
            nextItemIndex += 1
            let age = playbackTime - item.time
            guard age >= 0, age < displayDuration(for: item) else { continue }
            spawn(item, at: playbackTime, animated: true)
            spawnedCount += 1
        }
    }

    private func skipExpiredItems(at playbackTime: TimeInterval) {
        let maximumDuration = maximumDisplayDuration()
        while nextItemIndex < items.count, playbackTime - items[nextItemIndex].time > maximumDuration {
            nextItemIndex += 1
        }
    }

    private func spawn(_ item: DanmakuItem, at playbackTime: TimeInterval, animated: Bool) {
        guard item.isSupported, bounds.width > 20, bounds.height > 20 else { return }
        trimActiveItemsIfNeeded()

        let fontSize = fontSize(for: item)
        let font = UIFont.systemFont(ofSize: fontSize, weight: settings.fontWeight.uiFontWeight)
        let textSize = measuredTextSize(for: item, font: font)
        let labelSize = CGSize(
            width: min(max(textSize.width + 18, 44), bounds.width * 1.45),
            height: max(textSize.height + 8, fontSize + 8)
        )
        let label = dequeueLabel()
        configure(label, for: item, font: font, size: labelSize)

        let duration = displayDuration(for: item)
        let age = min(max(0, playbackTime - item.time), duration)
        let remainingPlaybackDuration = max(0.05, duration - age)
        let animationDuration = animated ? remainingPlaybackDuration / playbackRate : 0
        let band = displayBand()
        let laneHeight = max(labelSize.height, fontSize + 10)
        let laneCount = max(1, Int(max(1, band.height) / laneHeight))
        let lane = laneIndex(for: item, laneCount: laneCount, laneHeight: laneHeight, at: item.time)
        let y = yPosition(for: item, lane: lane, laneHeight: laneHeight, band: band, labelSize: labelSize)

        addSubview(label)
        let id = item.id
        let completion = animated ? DanmakuAnimationCompletionDelegate { [weak self, weak label] in
            guard let self, let label else { return }
            self.removeActiveLabel(id: id, label: label, shouldRecycle: true)
        } : nil
        activeEntries[id] = ActiveEntry(
            id: id,
            label: label,
            completion: completion,
            createdAt: CACurrentMediaTime()
        )

        if item.isScrolling {
            let travelDistance = bounds.width + labelSize.width
            let progress = min(max(age / duration, 0), 1)
            let startX = bounds.width + labelSize.width / 2 - travelDistance * progress
            let endX = -labelSize.width / 2
            label.center = CGPoint(x: animated ? endX : startX, y: y)
            if animated {
                let animation = CABasicAnimation(keyPath: "position.x")
                animation.fromValue = startX
                animation.toValue = endX
                animation.duration = animationDuration
                animation.timingFunction = CAMediaTimingFunction(name: .linear)
                animation.isRemovedOnCompletion = true
                animation.delegate = completion
                label.layer.add(animation, forKey: "danmaku.scroll")
            }
        } else {
            label.center = CGPoint(x: bounds.midX, y: y)
            if animated {
                let animation = CAKeyframeAnimation(keyPath: "opacity")
                animation.values = [0, 1, 1, 0]
                animation.keyTimes = [0, 0.06, 0.92, 1]
                animation.duration = animationDuration
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animation.isRemovedOnCompletion = true
                animation.delegate = completion
                label.layer.opacity = 0
                label.layer.add(animation, forKey: "danmaku.opacity")
            }
        }
    }

    private func configure(_ label: UILabel, for item: DanmakuItem, font: UIFont, size: CGSize) {
        label.text = item.text
        label.font = font
        label.textAlignment = .center
        label.numberOfLines = 1
        label.lineBreakMode = .byClipping
        label.textColor = UIColor.danmakuRGB(item.color).withAlphaComponent(settings.opacity)
        label.alpha = 1
        label.layer.opacity = 1
        label.frame = CGRect(origin: .zero, size: size)
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowOpacity = 0.92
        label.layer.shadowRadius = 1.4
        label.layer.shadowOffset = CGSize(width: 0, height: 1)
        label.layer.shouldRasterize = true
        label.layer.rasterizationScale = UIScreen.main.scale
        label.layer.allowsEdgeAntialiasing = true
    }

    private func dequeueLabel() -> UILabel {
        if let label = reusableLabels.popLast() {
            label.layer.removeAllAnimations()
            return label
        }
        let label = UILabel()
        label.backgroundColor = .clear
        label.isOpaque = false
        return label
    }

    private func recycle(_ label: UILabel) {
        label.text = nil
        label.layer.removeAllAnimations()
        label.removeFromSuperview()
        guard reusableLabels.count < 72 else { return }
        reusableLabels.append(label)
    }

    private func clearActiveLabels() {
        let entries = activeEntries.values
        activeEntries.removeAll(keepingCapacity: true)
        for entry in entries {
            entry.completion?.cancel()
            entry.label.layer.removeAllAnimations()
            recycle(entry.label)
        }
    }

    private func removeActiveLabel(id: String, label: UILabel, shouldRecycle: Bool) {
        guard let entry = activeEntries[id], entry.label === label else { return }
        entry.completion?.cancel()
        activeEntries[id] = nil
        label.layer.removeAllAnimations()
        if shouldRecycle {
            recycle(label)
        } else {
            label.removeFromSuperview()
        }
    }

    private func trimActiveItemsIfNeeded() {
        let overflow = activeEntries.count - maxActiveCount + 1
        guard overflow > 0 else { return }
        let removableEntries = activeEntries.values
            .sorted { $0.createdAt < $1.createdAt }
            .prefix(overflow)
        for entry in removableEntries {
            removeActiveLabel(id: entry.id, label: entry.label, shouldRecycle: true)
        }
    }

    private func measuredTextSize(for item: DanmakuItem, font: UIFont) -> CGSize {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let size = (item.text as NSString).boundingRect(
            with: CGSize(width: bounds.width * 1.6, height: font.pointSize + 12),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        ).size
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }

    private func displayBand() -> CGRect {
        let usableMinY = max(0, topInset)
        let usableMaxY = max(usableMinY + 1, bounds.height - max(0, bottomInset))
        let usableHeight = max(1, usableMaxY - usableMinY)
        switch settings.displayArea {
        case .topHalf:
            return CGRect(x: 0, y: usableMinY, width: bounds.width, height: usableHeight * 0.52)
        case .center:
            let height = usableHeight * 0.46
            return CGRect(x: 0, y: usableMinY + (usableHeight - height) / 2, width: bounds.width, height: height)
        case .full:
            return CGRect(x: 0, y: usableMinY, width: bounds.width, height: usableHeight)
        }
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
            return min(max(y, labelSize.height / 2), bounds.height - labelSize.height / 2)
        }
        if item.isTopAnchored {
            let anchoredLaneCount = min(3, max(1, Int(max(1, band.height) / laneHeight)))
            let anchoredLane = stableLane(for: item.id, laneCount: anchoredLaneCount)
            let y = band.minY + laneHeight * (CGFloat(anchoredLane) + 0.5)
            return min(max(y, labelSize.height / 2), bounds.height - labelSize.height / 2)
        }
        let y = band.minY + laneHeight * (CGFloat(lane) + 0.5)
        return min(max(y, labelSize.height / 2), bounds.height - labelSize.height / 2)
    }

    private func laneIndex(for item: DanmakuItem, laneCount: Int, laneHeight _: CGFloat, at itemTime: TimeInterval) -> Int {
        guard laneCount > 1, item.isScrolling else { return 0 }
        let startLane = stableLane(for: item.id, laneCount: laneCount)
        for offset in 0..<laneCount {
            let lane = (startLane + offset) % laneCount
            if (laneReleaseTimes[lane] ?? 0) <= itemTime {
                laneReleaseTimes[lane] = itemTime + laneCooldown
                return lane
            }
        }
        let lane = startLane
        laneReleaseTimes[lane] = itemTime + laneCooldown
        return lane
    }

    private var laneCooldown: TimeInterval {
        bounds.width > 640 ? 1.0 : 1.25
    }

    private func displayDuration(for item: DanmakuItem) -> TimeInterval {
        item.isScrolling ? scrollDuration : 4.2
    }

    private func maximumDisplayDuration() -> TimeInterval {
        max(scrollDuration, 4.2)
    }

    private var scrollDuration: TimeInterval {
        bounds.width > 640 ? 8.4 : 7.2
    }

    private var maxActiveCount: Int {
        bounds.width > 640 ? 56 : 32
    }

    private var maxSpawnPerTick: Int {
        bounds.width > 640 ? 8 : 5
    }

    private func fontSize(for item: DanmakuItem) -> CGFloat {
        let compactScale = bounds.width > 640 ? 0.86 : 0.70
        let maximumSize: CGFloat = bounds.width > 640 ? 24 : 18
        let minimumSize: CGFloat = bounds.width > 640 ? 15 : 13
        let scaledSize = CGFloat(item.fontSize) * compactScale * CGFloat(settings.fontScale)
        return min(max(scaledSize, minimumSize * 0.9), maximumSize * 1.35)
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

    private static func signature(for items: [DanmakuItem]) -> String {
        guard let first = items.first, let last = items.last else { return "0" }
        return "\(items.count)|\(first.id)|\(last.id)|\(first.time)|\(last.time)"
    }
}

private final class DanmakuAnimationCompletionDelegate: NSObject, CAAnimationDelegate {
    private let completion: () -> Void
    private var isCancelled = false

    init(completion: @escaping () -> Void) {
        self.completion = completion
    }

    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        guard flag, !isCancelled else { return }
        completion()
    }

    func cancel() {
        isCancelled = true
    }
}

private extension UIColor {
    static func danmakuRGB(_ rgb: UInt32) -> UIColor {
        let red = CGFloat((rgb >> 16) & 0xFF) / 255
        let green = CGFloat((rgb >> 8) & 0xFF) / 255
        let blue = CGFloat(rgb & 0xFF) / 255
        return UIColor(red: red, green: green, blue: blue, alpha: 1)
    }
}

private extension DanmakuFontWeightOption {
    var uiFontWeight: UIFont.Weight {
        switch self {
        case .regular:
            return .regular
        case .semibold:
            return .semibold
        case .bold:
            return .bold
        }
    }
}
