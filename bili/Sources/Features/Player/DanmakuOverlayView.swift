import SwiftUI

struct DanmakuOverlayView: View {
    let items: [DanmakuItem]
    let currentTime: TimeInterval
    let isPlaying: Bool
    let playbackRate: Double
    let isEnabled: Bool
    let hasPresentedPlayback: Bool
    let topInset: CGFloat
    let bottomInset: CGFloat

    @State private var anchorPlaybackTime: TimeInterval = 0
    @State private var anchorDate = Date()

    var body: some View {
        GeometryReader { geometry in
            if isEnabled, hasPresentedPlayback, !items.isEmpty {
                TimelineView(.animation) { timeline in
                    let playbackTime = effectivePlaybackTime(at: timeline.date)
                    ZStack {
                        ForEach(visibleItems(at: playbackTime, in: geometry.size)) { item in
                            DanmakuText(item: item, size: fontSize(for: item, in: geometry.size))
                                .opacity(opacity(for: item, at: playbackTime, in: geometry.size))
                                .position(position(for: item, at: playbackTime, in: geometry.size))
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear(perform: syncPlaybackAnchor)
        .onChange(of: currentTime) { _, _ in
            syncPlaybackAnchor()
        }
        .onChange(of: isPlaying) { _, _ in
            syncPlaybackAnchor()
        }
        .onChange(of: playbackRate) { _, _ in
            syncPlaybackAnchor()
        }
    }

    private func effectivePlaybackTime(at date: Date) -> TimeInterval {
        guard isPlaying else { return max(0, currentTime) }
        let elapsed = max(0, date.timeIntervalSince(anchorDate))
        return max(0, anchorPlaybackTime + elapsed * max(playbackRate, 0.1))
    }

    private func syncPlaybackAnchor() {
        anchorPlaybackTime = max(0, currentTime)
        anchorDate = Date()
    }

    private func visibleItems(at playbackTime: TimeInterval, in size: CGSize) -> [DanmakuItem] {
        guard size.width > 20, size.height > 20 else { return [] }
        let latestVisibleStart = playbackTime - scrollDuration(in: size)
        let startIndex = firstItemIndex(atOrAfter: latestVisibleStart)
        let endIndex = firstItemIndex(after: playbackTime)
        guard startIndex < endIndex else { return [] }

        let maxCount = maxVisibleItems(in: size)
        let window = items[startIndex..<endIndex].filter { item in
            playbackTime - item.time <= displayDuration(for: item, in: size)
        }
        guard window.count > maxCount else { return Array(window) }
        return Array(window.suffix(maxCount))
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

    private func position(for item: DanmakuItem, at playbackTime: TimeInterval, in size: CGSize) -> CGPoint {
        let age = max(0, playbackTime - item.time)
        let fontSize = fontSize(for: item, in: size)
        let laneHeight = fontSize + 10
        let laneCount = max(1, Int(max(1, size.height - topInset - bottomInset) / laneHeight))
        let lane = stableLane(for: item.id, laneCount: laneCount)

        if item.isTopAnchored || item.isBottomAnchored {
            let anchoredLaneCount = min(laneCount, 3)
            let anchoredLane = stableLane(for: item.id, laneCount: max(1, anchoredLaneCount))
            let y: CGFloat
            if item.isBottomAnchored {
                y = size.height - bottomInset - laneHeight * (CGFloat(anchoredLane) + 0.5)
            } else {
                y = topInset + laneHeight * (CGFloat(anchoredLane) + 0.5)
            }
            return CGPoint(x: size.width / 2, y: min(max(y, fontSize), size.height - fontSize))
        }

        let duration = scrollDuration(in: size)
        let progress = min(max(age / duration, 0), 1)
        let textWidth = estimatedWidth(for: item, fontSize: fontSize, in: size)
        let travelDistance = size.width + textWidth
        let x = size.width + textWidth / 2 - travelDistance * progress
        let y = topInset + laneHeight * (CGFloat(lane) + 0.5)
        return CGPoint(x: x, y: min(max(y, fontSize), size.height - fontSize))
    }

    private func opacity(for item: DanmakuItem, at playbackTime: TimeInterval, in size: CGSize) -> Double {
        let age = max(0, playbackTime - item.time)
        let duration = displayDuration(for: item, in: size)
        guard duration > 0 else { return 0 }
        let fadeIn = min(age / 0.18, 1)
        let fadeOut = min((duration - age) / 0.22, 1)
        return max(0, min(fadeIn, fadeOut))
    }

    private func displayDuration(for item: DanmakuItem, in size: CGSize) -> TimeInterval {
        item.isScrolling ? scrollDuration(in: size) : 4.2
    }

    private func scrollDuration(in size: CGSize) -> TimeInterval {
        size.width > 640 ? 8.4 : 7.2
    }

    private func maxVisibleItems(in size: CGSize) -> Int {
        size.width > 640 ? 110 : 72
    }

    private func fontSize(for item: DanmakuItem, in size: CGSize) -> CGFloat {
        let compactScale = size.width > 640 ? 0.88 : 0.72
        let maximumSize: CGFloat = size.width > 640 ? 25 : 19
        let minimumSize: CGFloat = size.width > 640 ? 15 : 13
        return min(max(CGFloat(item.fontSize) * compactScale, minimumSize), maximumSize)
    }

    private func estimatedWidth(for item: DanmakuItem, fontSize: CGFloat, in size: CGSize) -> CGFloat {
        let scalarCount = max(1, item.text.unicodeScalars.count)
        let width = CGFloat(scalarCount) * fontSize * 0.64 + 16
        return min(max(width, 44), size.width * 1.35)
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

private struct DanmakuText: View {
    let item: DanmakuItem
    let size: CGFloat

    var body: some View {
        Text(item.text)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.danmakuRGB(item.color))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .shadow(color: .black.opacity(0.95), radius: 1.2)
            .shadow(color: .black.opacity(0.75), radius: 2.2, y: 1)
    }
}

private extension Color {
    static func danmakuRGB(_ rgb: UInt32) -> Color {
        let red = Double((rgb >> 16) & 0xFF) / 255
        let green = Double((rgb >> 8) & 0xFF) / 255
        let blue = Double(rgb & 0xFF) / 255
        return Color(red: red, green: green, blue: blue)
    }
}
