import Combine
import Foundation
import UIKit

@MainActor
final class DanmakuRendererDiagnostics: ObservableObject {
    static let shared = DanmakuRendererDiagnostics()

    struct DanmakuKitSummary {
        struct EntryEvent {
            let identifier: String
            let path: String
            let source: String
            let age: TimeInterval
            var drawMilliseconds: Double?
        }

        var shootRequests = 0
        var syncRequests = 0
        var lateDrops = 0
        var activeItems = 0
        var peakActiveItems = 0
        var rebuilds = 0
        var lastRebuildReason = "none"
        var displayLinkTicks = 0
        var displayLinkIntervals: [Double] = []
        var previousDisplayLinkTimestamp: CFTimeInterval?
        var displayLinkGapCount = 0
        var displayLinkWorkCount = 0
        var totalDisplayLinkWorkMilliseconds = 0.0
        var maxDisplayLinkWorkMilliseconds = 0.0
        var cellDrawCount = 0
        var totalCellDrawMilliseconds = 0.0
        var maxCellDrawMilliseconds = 0.0
        var delayedCellDrawCount = 0
        var entryEvents: [EntryEvent] = []
        var emoteImageLoads = 0
        var emoteImageLoadFailures = 0

        var averageDisplayLinkWorkMilliseconds: Double? {
            guard displayLinkWorkCount > 0 else { return nil }
            return totalDisplayLinkWorkMilliseconds / Double(displayLinkWorkCount)
        }

        var averageCellDrawMilliseconds: Double? {
            guard cellDrawCount > 0 else { return nil }
            return totalCellDrawMilliseconds / Double(cellDrawCount)
        }

        var medianDisplayLinkHz: Double {
            guard !displayLinkIntervals.isEmpty else { return 0 }
            let sorted = displayLinkIntervals.sorted()
            let median = sorted[sorted.count / 2]
            return median > 0 ? 1 / median : 0
        }
    }

    @Published private(set) var isRecording = false
    @Published private(set) var revision = 0
    private(set) var startedAt: Date?
    private(set) var danmakuKitSummary = DanmakuKitSummary()

    func start() {
        danmakuKitSummary = DanmakuKitSummary()
        startedAt = Date()
        isRecording = true
        revision &+= 1
    }

    func stop() {
        isRecording = false
        revision &+= 1
    }

    func refresh() {
        guard isRecording else { return }
        revision &+= 1
    }

    func recordDanmakuKitEntry(
        identifier: String,
        path: String,
        age: TimeInterval,
        source: String,
        activeItems: Int
    ) {
        guard isRecording else { return }
        switch path {
        case "shoot":
            danmakuKitSummary.shootRequests += 1
        case "sync":
            danmakuKitSummary.syncRequests += 1
        case "late-drop":
            danmakuKitSummary.lateDrops += 1
        default:
            break
        }
        recordDanmakuKitActiveItems(activeItems)
        danmakuKitSummary.entryEvents.append(
            DanmakuKitSummary.EntryEvent(
                identifier: identifier,
                path: path,
                source: source,
                age: max(0, age),
                drawMilliseconds: nil
            )
        )
        if danmakuKitSummary.entryEvents.count > 40 {
            danmakuKitSummary.entryEvents.removeFirst(danmakuKitSummary.entryEvents.count - 40)
        }
    }

    func recordDanmakuKitRebuild(reason: String) {
        guard isRecording else { return }
        danmakuKitSummary.rebuilds += 1
        danmakuKitSummary.lastRebuildReason = reason
    }

    func recordDanmakuKitDisplayLinkTick(
        timestamp: CFTimeInterval,
        expectedInterval: CFTimeInterval
    ) {
        guard isRecording else { return }
        danmakuKitSummary.displayLinkTicks += 1
        if let previous = danmakuKitSummary.previousDisplayLinkTimestamp {
            let interval = timestamp - previous
            if interval > 0, interval < 1 {
                danmakuKitSummary.displayLinkIntervals.append(interval)
                if danmakuKitSummary.displayLinkIntervals.count > 512 {
                    danmakuKitSummary.displayLinkIntervals.removeFirst()
                }
                let expected = max(0, expectedInterval)
                if expected > 0, interval > max(expected * 1.5, expected + 0.008) {
                    danmakuKitSummary.displayLinkGapCount += 1
                }
            }
        }
        danmakuKitSummary.previousDisplayLinkTimestamp = timestamp
    }

    func recordDanmakuKitDisplayLinkWork(milliseconds: Double) {
        guard isRecording, milliseconds.isFinite else { return }
        let work = max(0, milliseconds)
        danmakuKitSummary.displayLinkWorkCount += 1
        danmakuKitSummary.totalDisplayLinkWorkMilliseconds += work
        danmakuKitSummary.maxDisplayLinkWorkMilliseconds = max(
            danmakuKitSummary.maxDisplayLinkWorkMilliseconds,
            work
        )
    }

    func recordDanmakuKitCellDraw(identifier: String, milliseconds: Double) {
        guard isRecording, milliseconds.isFinite else { return }
        let duration = max(0, milliseconds)
        danmakuKitSummary.cellDrawCount += 1
        danmakuKitSummary.totalCellDrawMilliseconds += duration
        danmakuKitSummary.maxCellDrawMilliseconds = max(
            danmakuKitSummary.maxCellDrawMilliseconds,
            duration
        )
        if duration > 16.7 {
            danmakuKitSummary.delayedCellDrawCount += 1
        }
        if let index = danmakuKitSummary.entryEvents.lastIndex(where: { $0.identifier == identifier }) {
            danmakuKitSummary.entryEvents[index].drawMilliseconds = duration
        }
    }

    func recordDanmakuKitActiveItems(_ count: Int) {
        guard isRecording else { return }
        danmakuKitSummary.activeItems = max(0, count)
        danmakuKitSummary.peakActiveItems = max(
            danmakuKitSummary.peakActiveItems,
            danmakuKitSummary.activeItems
        )
    }

    func recordDanmakuKitEmoteImageLoad(succeeded: Bool) {
        guard isRecording else { return }
        if succeeded {
            danmakuKitSummary.emoteImageLoads += 1
        } else {
            danmakuKitSummary.emoteImageLoadFailures += 1
        }
    }

    func makeReport() -> String {
        let formatter = ISO8601DateFormatter()
        let duration = startedAt.map { max(0, Date().timeIntervalSince($0)) } ?? 0
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let summary = danmakuKitSummary
        var lines = [
            "DanmakuKit Renderer Diagnostics",
            "time: \(formatter.string(from: Date()))",
            "capture: \(isRecording ? "recording" : "stopped"), \(String(format: "%.1f", duration)) sec",
            "device: \(UIDevice.current.model)",
            "iOS: \(UIDevice.current.systemVersion)",
            "app: \(appVersion) (\(build))",
            "display-link ticks/median Hz/gaps: \(summary.displayLinkTicks)/\(String(format: "%.1f", summary.medianDisplayLinkHz))/\(summary.displayLinkGapCount)",
            "display-link work count/average/max: \(summary.displayLinkWorkCount)/\(summary.averageDisplayLinkWorkMilliseconds.map { String(format: "%.3f ms", $0) } ?? "not measured")/\(String(format: "%.3f ms", summary.maxDisplayLinkWorkMilliseconds))",
            "shoot/sync/late-drop entries: \(summary.shootRequests)/\(summary.syncRequests)/\(summary.lateDrops)",
            "rebuilds/last reason: \(summary.rebuilds)/\(summary.lastRebuildReason)",
            "text draw count/average/max/>16.7ms: \(summary.cellDrawCount)/\(summary.averageCellDrawMilliseconds.map { String(format: "%.3f ms", $0) } ?? "not measured")/\(summary.cellDrawCount == 0 ? "not measured" : String(format: "%.3f ms", summary.maxCellDrawMilliseconds))/\(summary.delayedCellDrawCount)",
            "active/peak active danmaku: \(summary.activeItems)/\(summary.peakActiveItems)",
            "emote image loads/failures: \(summary.emoteImageLoads)/\(summary.emoteImageLoadFailures)",
            "recent entry events (id suffix, path, age, source, draw):"
        ]
        for event in summary.entryEvents {
            let draw = event.drawMilliseconds.map { String(format: "%.3f ms", $0) } ?? "pending"
            lines.append(
                "  \(event.identifier.suffix(8)) \(event.path) age=\(String(format: "%.3f", event.age))s source=\(event.source) draw=\(draw)"
            )
        }
        return lines.joined(separator: "\n")
    }
}
