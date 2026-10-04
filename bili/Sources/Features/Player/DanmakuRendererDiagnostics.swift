import Combine
import Foundation
import UIKit
import QuartzCore

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

    #if DEBUG
    struct TimingSummary {
        var count = 0
        var total = 0.0
        var maximum = 0.0
        var average: Double? { count > 0 ? total / Double(count) : nil }
        mutating func record(_ milliseconds: Double?) {
            guard let milliseconds, milliseconds.isFinite, milliseconds >= 0 else { return }
            count += 1; total += milliseconds; maximum = max(maximum, milliseconds)
        }
        var report: String {
            guard let average else { return "-/- (n=0)" }
            return String(format: "%.3f/%.3f (n=%d)", average, maximum, count)
        }
    }
    struct LoadSummary {
        var samples = 0
        var total = 0
        var minimum: Int?
        var maximum = 0
        mutating func record(_ value: Int) {
            let value = max(0, value)
            samples += 1; total += value
            minimum = min(minimum ?? value, value); maximum = max(maximum, value)
        }
        var report: String {
            guard samples > 0 else { return "-/-/- (n=0)" }
            return String(format: "%.1f/%d/%d (n=%d)", Double(total) / Double(samples), minimum ?? 0, maximum, samples)
        }
    }
    struct BenchmarkConfiguration {
        let renderer: String
        let density: Int
        let requestedFPS: Int?
        let playbackRate: Double
        let viewport: CGSize
    }
    private var benchmarkEnvironment: PlaybackEnvironment?
    private(set) var benchmarkConfiguration: BenchmarkConfiguration?
    private(set) var kitLoad = LoadSummary()
    func recordDanmakuKitFrameLoad(_ active: Int) {
        guard isRecording else { return }
        kitLoad.record(active)
    }
    struct MetalSummary {
        var sceneEvents: [String] = []
        var renderFailures: [String: Int] = [:]
        var emptyGlyphFrames = 0
        var scenePreparation = TimingSummary()
        var drawableAcquisition = TimingSummary()
        var encoding = TimingSummary()
        var commit = TimingSummary()
        var automaticFrames = 0
        var manualRefreshFrames = 0
        var automaticDrawableAcquisition = TimingSummary()
        var manualDrawableAcquisition = TimingSummary()
        var activeLoad = LoadSummary()
        var glyphLoad = LoadSummary()
        var drawCallLoad = LoadSummary()
        var active = 0
        var peakActive = 0
        var glyphs = 0
        var drawCalls = 0
        var pages = 0
        var usedPixels = 0
        var capacityPixels = 0
        var rejectedGlyphs = 0
        var skippedFrames = 0
        var firstSkippedCount: Int?
        var frames = 0
        var requestedFPS = 0
        var displayMaximumFPS = 0
        var preparationTotalMs = 0.0
        var preparationMaxMs = 0.0
        var gpuSamples = 0
        var gpuTotalMs = 0.0
        var previousTimestamp: CFTimeInterval?
        var intervals: [Double] = []
        var callbackGaps = 0
        var medianFPS: Double? {
            guard !intervals.isEmpty else { return nil }
            let median = intervals.sorted()[intervals.count / 2]
            return median > 0 ? 1 / median : nil
        }
        var cpuAverageMs: Double? { frames > 0 ? preparationTotalMs / Double(frames) : nil }
        var gpuAverageMs: Double? { gpuSamples > 0 ? gpuTotalMs / Double(gpuSamples) : nil }
    }
    var rendererType = "DanmakuKit"
    private(set) var metalSummary = MetalSummary()

    func recordMetalSceneEvent(_ reason: String, time: TimeInterval, before: Int, after: Int) {
        guard isRecording, time.isFinite else { return }
        let elapsed = captureDuration()
        metalSummary.sceneEvents.append(String(format: "at=%.3fs media=%.3fs reason=%@ active=%d→%d",
            elapsed, time, reason, before, after))
        if metalSummary.sceneEvents.count > 20 { metalSummary.sceneEvents.removeFirst() }
    }

    func recordMetalRenderFailure(_ reason: String, captureID: UUID? = nil) {
        guard isRecording, captureID == nil || captureID == self.captureID else { return }
        metalSummary.renderFailures[reason, default: 0] += 1
    }

    func recordMetalFrame(active: Int, glyphs: Int, drawCalls: Int, pages: Int,
                          usedPixels: Int, capacityPixels: Int, rejected: Int, skipped: Int,
                          preparationMs: Double, timestamp: CFTimeInterval, expectedInterval: Double,
                          requestedFPS: Int, displayMaximumFPS: Int,
                          scenePreparationMs: Double? = nil, drawableAcquisitionMs: Double? = nil,
                          encodingMs: Double? = nil, commitMs: Double? = nil, isManualRefresh: Bool = false) {
        guard isRecording else { return }
        if active > 0, glyphs == 0 { metalSummary.emptyGlyphFrames += 1 }
        if isManualRefresh {
            metalSummary.manualRefreshFrames += 1
            metalSummary.manualDrawableAcquisition.record(drawableAcquisitionMs)
        } else {
            metalSummary.automaticFrames += 1
            metalSummary.automaticDrawableAcquisition.record(drawableAcquisitionMs)
        }
        metalSummary.scenePreparation.record(scenePreparationMs)
        metalSummary.drawableAcquisition.record(drawableAcquisitionMs)
        metalSummary.encoding.record(encodingMs)
        metalSummary.commit.record(commitMs)
        metalSummary.activeLoad.record(active)
        metalSummary.glyphLoad.record(glyphs)
        metalSummary.drawCallLoad.record(drawCalls)
        metalSummary.active = active
        metalSummary.peakActive = max(metalSummary.peakActive, active)
        metalSummary.glyphs = glyphs
        metalSummary.drawCalls = drawCalls
        metalSummary.pages = pages
        metalSummary.usedPixels = usedPixels
        metalSummary.capacityPixels = capacityPixels
        metalSummary.rejectedGlyphs = rejected
        if metalSummary.firstSkippedCount == nil { metalSummary.firstSkippedCount = skipped }
        metalSummary.skippedFrames = max(0, skipped - (metalSummary.firstSkippedCount ?? skipped))
        metalSummary.frames += 1
        metalSummary.requestedFPS = requestedFPS
        metalSummary.displayMaximumFPS = displayMaximumFPS
        metalSummary.preparationTotalMs += preparationMs
        metalSummary.preparationMaxMs = max(metalSummary.preparationMaxMs, preparationMs)
        if !isManualRefresh, expectedInterval > 0, let previous = metalSummary.previousTimestamp {
            let gap = timestamp - previous
            if gap > 0, gap < 1 {
                metalSummary.intervals.append(gap)
                if metalSummary.intervals.count > 512 { metalSummary.intervals.removeFirst() }
                if expectedInterval > 0, gap > max(expectedInterval * 1.5, expectedInterval + 0.008) { metalSummary.callbackGaps += 1 }
            }
        }
        metalSummary.previousTimestamp = !isManualRefresh && expectedInterval > 0 ? timestamp : nil
    }
    func recordMetalGPU(milliseconds: Double?, captureID: UUID? = nil) {
        guard isRecording, captureID == nil || captureID == self.captureID,
              let milliseconds, milliseconds.isFinite, milliseconds >= 0 else { return }
        metalSummary.gpuSamples += 1
        metalSummary.gpuTotalMs += milliseconds
    }
    func clearMetalActiveCount() { metalSummary.active = 0; metalSummary.previousTimestamp = nil }
    func resetMetalCadence() { metalSummary.previousTimestamp = nil }
    #endif

    @Published private(set) var isRecording = false
    @Published private(set) var revision = 0
    private(set) var startedAt: Date?
    private(set) var captureID = UUID()
    private var startTimestamp: CFTimeInterval?
    private var stopTimestamp: CFTimeInterval?
    func captureDuration(at timestamp: CFTimeInterval = CACurrentMediaTime()) -> Double {
        guard let startTimestamp else { return 0 }
        return max(0, (stopTimestamp ?? timestamp) - startTimestamp)
    }
    private(set) var danmakuKitSummary = DanmakuKitSummary()

    func start(at timestamp: CFTimeInterval = CACurrentMediaTime()) {
        danmakuKitSummary = DanmakuKitSummary()
        #if DEBUG
        metalSummary = MetalSummary()
        kitLoad = LoadSummary()
        benchmarkConfiguration = nil
        benchmarkEnvironment = nil
        #endif
        captureID = UUID()
        startTimestamp = timestamp
        stopTimestamp = nil
        startedAt = Date()
        isRecording = true
        revision &+= 1
    }

    #if DEBUG
    func startBenchmark(_ configuration: BenchmarkConfiguration) {
        start()
        benchmarkConfiguration = configuration
        benchmarkEnvironment = .current
    }
    #endif

    func stop(at timestamp: CFTimeInterval = CACurrentMediaTime()) {
        guard isRecording else { return }
        stopTimestamp = timestamp
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

    func recordDanmakuKitCellDraw(identifier: String, milliseconds: Double, captureID: UUID? = nil) {
        guard isRecording, captureID == nil || captureID == self.captureID, milliseconds.isFinite else { return }
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
        let duration = captureDuration()
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let summary = danmakuKitSummary
        var lines = [
            "Danmaku Renderer Diagnostics",
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
        #if DEBUG
        lines.append("capture ID: \(captureID.uuidString)")
        if let configuration = benchmarkConfiguration {
            lines.append("fixture: local-text-v1; loop media time 7s → 1s (rebuild); overlap enabled")
            lines.append("benchmark renderer/density/requested callback FPS/rate/viewport pt: \(configuration.renderer)/\(configuration.density)/\(configuration.requestedFPS.map(String.init) ?? "default")/\(configuration.playbackRate)/\(Int(configuration.viewport.width))x\(Int(configuration.viewport.height))")
            if let environment = benchmarkEnvironment {
                lines.append("environment at start: lowPower=\(environment.isLowPowerModeEnabled) thermal=\(environment.thermalPressure)")
            }
            lines.append("Kit active avg/min/max: \(kitLoad.report)")
        }
        let metal = metalSummary
        lines.append("renderer: \(rendererType)")
        lines.append("Metal active/peak/glyphs/drawCalls: \(metal.active)/\(metal.peakActive)/\(metal.glyphs)/\(metal.drawCalls)")
        lines.append("Metal atlas pages/used/capacity/rejected (atlas lifetime): \(metal.pages)/\(metal.usedPixels)/\(metal.capacityPixels)/\(metal.rejectedGlyphs)")
        lines.append("Metal frames/callback median Hz/callback gaps/busy slot drops since first frame: \(metal.frames)/\(metal.medianFPS.map { String(format: "%.1f", $0) } ?? "-")/\(metal.callbackGaps)/\(metal.skippedFrames)")
        lines.append("Metal frame source automatic/manual refresh: \(metal.automaticFrames)/\(metal.manualRefreshFrames)")
        lines.append("Metal automatic drawable acquisition avg/max ms: \(metal.automaticDrawableAcquisition.report)")
        lines.append("Metal manual drawable acquisition avg/max ms: \(metal.manualDrawableAcquisition.report)")
        lines.append("Metal requested/display maximum FPS: \(metal.requestedFPS)/\(metal.displayMaximumFPS)")
        lines.append("Metal draw callback elapsed average/max ms (includes drawable acquisition): \(metal.cpuAverageMs.map { String(format: "%.3f", $0) } ?? "-")/\(String(format: "%.3f", metal.preparationMaxMs))")
        lines.append("Metal scene preparation avg/max ms: \(metal.scenePreparation.report)")
        lines.append("Metal render-pass + drawable acquisition avg/max ms: \(metal.drawableAcquisition.report)")
        lines.append("Metal encode/setup avg/max ms: \(metal.encoding.report)")
        lines.append("Metal commit avg/max ms: \(metal.commit.report)")
        lines.append("Metal active avg/min/max: \(metal.activeLoad.report)")
        lines.append("Metal glyphs avg/min/max: \(metal.glyphLoad.report)")
        lines.append("Metal draw calls avg/min/max: \(metal.drawCallLoad.report)")
        lines.append("Measurement scope: callback Hz is not presented FPS; gap counts are callback gaps, not measured dropped frames. Elapsed ms is not process CPU utilization. Kit display-link work excludes Core Animation/render-server work; text draw is per cell. Use Instruments for CPU/energy A/B.")
        lines.append("Metal GPU command average ms: \(metal.gpuAverageMs.map { String(format: "%.3f", $0) } ?? "-") (n=\(metal.gpuSamples))")
        lines.append("Metal active-without-glyph frames: \(metal.emptyGlyphFrames)")
        let failures = metal.renderFailures.keys.sorted().map { "\($0)=\(metal.renderFailures[$0] ?? 0)" }
        lines.append("Metal render failures: \(failures.isEmpty ? "none" : failures.joined(separator: ", "))")
        lines.append("Metal recent scene events (last 20; empty expiry and test loop rebuilds may be expected):")
        lines.append(contentsOf: metal.sceneEvents.map { "  " + $0 })
        #endif
        for event in summary.entryEvents {
            let draw = event.drawMilliseconds.map { String(format: "%.3f ms", $0) } ?? "pending"
            lines.append(
                "  \(event.identifier.suffix(8)) \(event.path) age=\(String(format: "%.3f", event.age))s source=\(event.source) draw=\(draw)"
            )
        }
        return lines.joined(separator: "\n")
    }
}
