import UIKit

/// Geometric adapter for Metal. DanmakuKit's private, cell-based tracks cannot
/// be used without creating animated views. Data, timing and admission rules
/// remain shared; no API loading or filtering business lives here.
final class MetalDanmakuTimeline {
    static let backwardClockCorrectionTolerance: TimeInterval = 0.2
    struct Entry {
        let item: DanmakuItem
        let size: CGSize
        let lane: Int
        let startX: CGFloat
        let y: CGFloat
        let velocity: CGFloat
        let endTime: TimeInterval
        var glyphScale: CGFloat = 1
        var fontScaleSettleStartHostTime: TimeInterval?
        var fontScaleSettleDuration: TimeInterval = 0

        func glyphScale(at hostTime: TimeInterval) -> CGFloat {
            guard let start = fontScaleSettleStartHostTime,
                  fontScaleSettleDuration > 0 else { return glyphScale }
            let progress = min(max((hostTime - start) / fontScaleSettleDuration, 0), 1)
            return glyphScale + (1 - glyphScale) * progress
        }

        func frame(at time: TimeInterval) -> CGRect {
            CGRect(x: startX - velocity * max(0, time - item.time), y: y,
                   width: size.width, height: size.height)
        }
    }

    private(set) var active: [Entry] = []
    private(set) var revision = 0
    private var items: [DanmakuItem] = []
    private var lastTime: TimeInterval?
    /// Use the same accepted clock for admission and the shader's lifetime gate.
    var presentationTime: TimeInterval? { lastTime }
    #if DEBUG
    private(set) var rebuildCount = 0
    private(set) var lastRebuildReason = "none"
    #endif
    private var nextExpiry = TimeInterval.infinity
    private var cursor = 0
    var viewport = CGSize.zero
    var settings = DanmakuSettings.default
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0
    var maximumActiveCount = 24

    func replaceItems(_ items: [DanmakuItem], at time: TimeInterval,
                      measure: (DanmakuItem) -> CGSize?) {
        self.items = normalizedItems(items)
        rebuild(at: time, measure: measure)
    }

    func canPreserveActiveEntries(with updatedItems: [DanmakuItem], at time: TimeInterval) -> Bool {
        canPreserveActiveEntries(withNormalizedItems: normalizedItems(updatedItems), at: time)
    }

    @discardableResult
    func replaceItemsPreservingActive(_ updatedItems: [DanmakuItem], at time: TimeInterval) -> Bool {
        let normalized = normalizedItems(updatedItems)
        guard canPreserveActiveEntries(withNormalizedItems: normalized, at: time) else { return false }
        items = normalized
        active.removeAll { $0.endTime <= time }
        cursor = index(after: time)
        lastTime = time
        nextExpiry = active.map(\.endTime).min() ?? .infinity
        revision &+= 1
        return true
    }

    /// Updates the future admission window without rebuilding active entries.
    /// Used only while the Metal stage is being resized.
    func replaceItemsKeepingActiveDuringStageTransition(_ updatedItems: [DanmakuItem], at time: TimeInterval) {
        guard time.isFinite else { return }
        items = normalizedItems(updatedItems)
        active.removeAll { $0.endTime <= time }
        cursor = index(after: time)
        lastTime = time
        nextExpiry = active.map(\.endTime).min() ?? .infinity
        revision &+= 1
    }

    /// Rebases active entries once after a stage transition. Media timestamps and
    /// lane identities are preserved; only their logical geometry is transformed.
    func rebaseActive(using transform: DanmakuStageTransform, at time: TimeInterval) {
        guard transform.scale.isFinite, transform.scale > 0,
              transform.translation.x.isFinite, transform.translation.y.isFinite else { return }
        active = active.compactMap { entry in
            guard entry.endTime > time else { return nil }
            let origin = transform.map(CGPoint(x: entry.startX, y: entry.y))
            return Entry(
                item: entry.item,
                size: CGSize(width: entry.size.width * transform.scale,
                             height: entry.size.height * transform.scale),
                lane: entry.lane,
                startX: origin.x,
                y: origin.y,
                velocity: entry.velocity * transform.scale,
                endTime: entry.endTime,
                glyphScale: entry.glyphScale * transform.scale
            )
        }
        nextExpiry = active.map(\.endTime).min() ?? .infinity
        lastTime = time
        revision &+= 1
    }

    /// Re-layouts active comments once for the settled viewport. Media lifetime
    /// and lane identity stay fixed while the Metal shader eases glyph scale.
    func normalizeActiveFonts(
        at time: TimeInterval,
        hostTime: TimeInterval,
        duration: TimeInterval,
        layouts: [String: (previous: DanmakuGlyphLayout, target: DanmakuGlyphLayout)]
    ) {
        guard time.isFinite, hostTime.isFinite, duration.isFinite, duration >= 0 else { return }
        active = active.compactMap { entry in
            guard entry.endTime > time else { return nil }
            guard let pair = layouts[entry.item.id], pair.previous.fontPointSize > 0,
                  pair.target.fontPointSize > 0 else { return entry }

            let scale = entry.glyphScale * pair.previous.fontPointSize / pair.target.fontPointSize
            guard scale.isFinite, scale >= 0.25, scale <= 8 else { return entry }
            let targetSize = pair.target.size
            let settling = duration > 0 && abs(scale - 1) > 0.005
            let initialScale = settling ? scale : 1
            let initialSize = CGSize(width: targetSize.width * initialScale,
                                     height: targetSize.height * initialScale)
            let startX = entry.item.isScrolling
                ? entry.startX
                : (viewport.width - targetSize.width) / 2
            let y = entry.item.isBottomAnchored
                ? entry.y + entry.size.height - targetSize.height
                : entry.y

            return Entry(
                item: entry.item,
                size: initialSize,
                lane: entry.lane,
                startX: startX,
                y: y,
                velocity: entry.velocity,
                endTime: entry.endTime,
                glyphScale: initialScale,
                fontScaleSettleStartHostTime: settling ? hostTime : nil,
                fontScaleSettleDuration: settling ? duration : 0
            )
        }
        nextExpiry = active.map(\.endTime).min() ?? .infinity
        lastTime = time
        revision &+= 1
    }

    /// Commits an in-progress scale animation before another resize interrupts it.
    @discardableResult
    func materializeFontScaleSettle(
        at hostTime: TimeInterval,
        layoutForItem: (DanmakuItem) -> DanmakuGlyphLayout?
    ) -> Bool {
        var changed = false
        active = active.map { entry in
            guard entry.fontScaleSettleStartHostTime != nil,
                  let layout = layoutForItem(entry.item) else { return entry }
            let scale = entry.glyphScale(at: hostTime)
            guard scale.isFinite, scale > 0 else { return entry }
            changed = true
            // The stage shader still applies center/bottom anchor compensation
            // from glyphScale. Keep the anchor origin unchanged when committing
            // the animation or an interrupted resize would apply it twice.
            return Entry(
                item: entry.item,
                size: CGSize(width: layout.size.width * scale, height: layout.size.height * scale),
                lane: entry.lane,
                startX: entry.startX,
                y: entry.y,
                velocity: entry.velocity,
                endTime: entry.endTime,
                glyphScale: scale
            )
        }
        if changed { revision &+= 1 }
        return changed
    }

    @discardableResult
    func completeFontScaleSettles(
        at hostTime: TimeInterval,
        layoutForItem: (DanmakuItem) -> DanmakuGlyphLayout?
    ) -> Bool {
        var changed = false
        active = active.map { entry in
            guard let start = entry.fontScaleSettleStartHostTime,
                  hostTime >= start + entry.fontScaleSettleDuration,
                  let layout = layoutForItem(entry.item) else { return entry }
            changed = true
            return Entry(item: entry.item, size: layout.size, lane: entry.lane,
                         startX: entry.startX, y: entry.y, velocity: entry.velocity,
                         endTime: entry.endTime, glyphScale: 1)
        }
        if changed {
            nextExpiry = active.map(\.endTime).min() ?? .infinity
            revision &+= 1
        }
        return changed
    }

    func hasActiveFontScaleSettle(at hostTime: TimeInterval) -> Bool {
        active.contains { entry in
            guard let start = entry.fontScaleSettleStartHostTime else { return false }
            return hostTime < start + entry.fontScaleSettleDuration
        }
    }

    private func canPreserveActiveEntries(
        withNormalizedItems updatedItems: [DanmakuItem],
        at time: TimeInterval
    ) -> Bool {
        guard time.isFinite, let lastTime, abs(time - lastTime) <= 1.25 else { return false }
        var updatedByID: [String: DanmakuItem] = [:]
        for item in updatedItems where updatedByID[item.id] == nil {
            updatedByID[item.id] = item
        }

        var hasUnchangedOverlap = false
        for item in items {
            guard let updatedItem = updatedByID[item.id] else { continue }
            guard item == updatedItem else { return false }
            hasUnchangedOverlap = true
        }
        return hasUnchangedOverlap
    }

    func rebuild(at time: TimeInterval, measure: (DanmakuItem) -> CGSize?, reason: String = "explicit") {
        #if DEBUG
        rebuildCount += 1
        lastRebuildReason = reason
        #endif
        clear()
        guard time.isFinite else { return }
        let start = index(after: time - (viewport.width > 640 ? 8.4 : 7.2))
        cursor = index(after: time)
        for item in items[start..<cursor].suffix(maximumActiveCount) {
            admit(item, at: time, measure: measure)
        }
        lastTime = time
    }

    func advance(to time: TimeInterval, measure: (DanmakuItem) -> CGSize?) {
        guard time.isFinite else { return }
        guard let lastTime else {
            rebuild(at: time, measure: measure, reason: "clock-initial")
            return
        }
        // The draw loop extrapolates between player clock samples. A small
        // correction backwards is not a seek: rebuilding loses admitted entries
        // that have since left the input window or no longer fit the latest cap.
        if time < lastTime, time >= lastTime - Self.backwardClockCorrectionTolerance {
            return
        }
        guard time >= lastTime, time - lastTime <= 1.25 else {
            rebuild(at: time, measure: measure, reason: time < lastTime ? "clock-backward-jump" : "clock-forward-gap")
            return
        }
        if time >= nextExpiry {
            active.removeAll { $0.endTime <= time }
            nextExpiry = active.map(\.endTime).min() ?? .infinity
            revision &+= 1
        }
        let end = index(after: time)
        if cursor < end {
            for item in items[cursor..<end] { admit(item, at: time, measure: measure) }
        }
        cursor = end
        self.lastTime = time
    }

    func clear() {
        active.removeAll(keepingCapacity: true)
        lastTime = nil
        cursor = 0
        nextExpiry = .infinity
        revision &+= 1
    }

    private func admit(_ item: DanmakuItem, at time: TimeInterval,
                       measure: (DanmakuItem) -> CGSize?) {
        guard viewport.width.isFinite, viewport.height.isFinite, viewport.width > 0, viewport.height > 0,
              active.count < maximumActiveCount,
              DanmakuRenderPolicy.supports(item, settings: settings),
              time >= item.time,
              !active.contains(where: { $0.item.id == item.id }),
              let size = measure(item), size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return }
        let duration = DanmakuRenderPolicy.duration(for: item, viewportWidth: viewport.width)
        guard time - item.time < duration else { return }
        let top = min(max(0, topInset + settings.danmakuKit.topPadding), viewport.height)
        let bottom = min(max(0, bottomInset + settings.danmakuKit.bottomPadding), max(0, viewport.height - top))
        let usable = max(0, viewport.height - top - bottom)
        // Prevent different glyph heights from overlapping adjacent lanes.
        let height = max(CGFloat(settings.danmakuKit.trackHeight), size.height)
        let area = usable * settings.danmakuKit.displayArea.fraction
        let lanes = max(0, Int(area / height))
        guard lanes > 0 else { return }
        let velocity: CGFloat = item.isScrolling ? (viewport.width + size.width) / duration : 0
        let startX = item.isScrolling ? viewport.width : (viewport.width - size.width) / 2
        let candidates = item.isBottomAnchored ? Array((0..<lanes).reversed()) : Array(0..<lanes)
        var chosen: Entry?
        var bestCount = Int.max
        for lane in candidates {
            let y = item.isBottomAnchored
                ? top + usable - area + CGFloat(lane) * height
                : top + CGFloat(lane) * height
            let entry = Entry(item: item, size: size, lane: lane, startX: startX, y: y,
                              velocity: velocity, endTime: item.time + duration)
            let overlappingRows = active.filter { $0.y < y + size.height && $0.y + $0.size.height > y }
            if settings.danmakuKit.allowsDanmakuOverlap {
                if overlappingRows.count < bestCount { chosen = entry; bestCount = overlappingRows.count }
            } else if overlappingRows.allSatisfy({ !willCollide($0, entry, at: time) }) {
                chosen = entry
                break
            }
        }
        guard let chosen else { return }
        active.append(chosen)
        nextExpiry = min(nextExpiry, chosen.endTime)
        revision &+= 1
    }

    private func willCollide(_ a: Entry, _ b: Entry, at time: TimeInterval) -> Bool {
        // Both ends of the common lifetime: linear motion cannot cross in between
        // without overlap at an end or reversal of the horizontal ordering.
        let end = min(a.endTime, b.endTime)
        let firstA = a.frame(at: time), firstB = b.frame(at: time)
        let endA = a.frame(at: end), endB = b.frame(at: end)
        let gap: CGFloat = 10
        let bFollowsA = firstB.minX >= firstA.maxX + gap && endB.minX >= endA.maxX + gap
        let aFollowsB = firstA.minX >= firstB.maxX + gap && endA.minX >= endB.maxX + gap
        return !(bFollowsA || aFollowsB)
    }

    private func index(after time: TimeInterval) -> Int {
        var low = 0, high = items.count
        while low < high {
            let mid = (low + high) / 2
            if items[mid].time <= time { low = mid + 1 } else { high = mid }
        }
        return low
    }

    private func normalizedItems(_ items: [DanmakuItem]) -> [DanmakuItem] {
        items.filter { $0.time.isFinite && $0.fontSize.isFinite }.sorted {
            $0.time == $1.time ? $0.id < $1.id : $0.time < $1.time
        }
    }
}
