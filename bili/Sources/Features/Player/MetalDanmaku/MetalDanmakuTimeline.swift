import UIKit

/// Geometric adapter for Metal. DanmakuKit's private, cell-based tracks cannot
/// be used without creating animated views. Data, timing and admission rules
/// remain shared; no API loading or filtering business lives here.
final class MetalDanmakuTimeline {
    struct Entry {
        let item: DanmakuItem
        let size: CGSize
        let lane: Int
        let startX: CGFloat
        let y: CGFloat
        let velocity: CGFloat
        let endTime: TimeInterval

        func frame(at time: TimeInterval) -> CGRect {
            CGRect(x: startX - velocity * max(0, time - item.time), y: y,
                   width: size.width, height: size.height)
        }
    }

    private(set) var active: [Entry] = []
    private(set) var revision = 0
    private var items: [DanmakuItem] = []
    private var lastTime: TimeInterval?
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

    func rebuild(at time: TimeInterval, measure: (DanmakuItem) -> CGSize?) {
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
        guard let lastTime, time >= lastTime, time - lastTime <= 1.25 else {
            rebuild(at: time, measure: measure)
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
