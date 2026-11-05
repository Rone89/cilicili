import QuartzCore
import UIKit

/// HDR 播放期间的 UI 帧率 / 卡顿探针。
///
/// 仅当播放源为 HDR 时运行，每 5 秒把一窗口的帧间隔统计写入
/// `Documents/player-diagnostics.log`（事件类型 `卡顿`），用于区分
/// “视频解码/缓冲卡”与“详情页 UI 合成卡”，并记录 EDR headroom 与热状态。
@MainActor
final class PlaybackHitchMonitor: NSObject {
    static let shared = PlaybackHitchMonitor()

    private struct Context {
        let metricsID: String
        let quality: Int?
        let dynamicRange: String
    }

    private let windowDuration: CFTimeInterval = 5
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var windowStart: CFTimeInterval = 0
    private var intervals: [Double] = []
    private var context: Context?

    private override init() {
        super.init()
    }

    func start(metricsID: String, quality: Int?, dynamicRange: BiliVideoDynamicRange) {
        let nextContext = Context(
            metricsID: metricsID,
            quality: quality,
            dynamicRange: dynamicRange.rawValue
        )
        guard displayLink == nil else {
            context = nextContext
            return
        }
        context = nextContext
        windowStart = CACurrentMediaTime()
        lastTimestamp = nil
        intervals.removeAll(keepingCapacity: true)
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = nil
        windowStart = 0
        intervals.removeAll(keepingCapacity: false)
        context = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        let timestamp = link.timestamp
        if let lastTimestamp {
            intervals.append(timestamp - lastTimestamp)
        }
        lastTimestamp = timestamp
        guard timestamp - windowStart >= windowDuration, !intervals.isEmpty else { return }
        publish(at: timestamp)
    }

    private func publish(at timestamp: CFTimeInterval) {
        guard let context else { return }
        let sorted = intervals.sorted()
        let count = sorted.count
        let averageMilliseconds = sorted.reduce(0, +) / Double(count) * 1_000
        let p95Milliseconds = sorted[min(count - 1, Int(Double(count) * 0.95))] * 1_000
        let maxMilliseconds = (sorted.last ?? 0) * 1_000
        let targetSeconds = expectedFrameDuration()
        let hitchThreshold = max(targetSeconds * 1.8, 0.034)
        let hitchCount = sorted.filter { $0 > hitchThreshold }.count
        let framesPerSecond = Double(count) / max(timestamp - windowStart, 0.001)
        let screen = activeScreen()
        let edrHeadroom = screen.map { String(format: "%.2f", $0.currentEDRHeadroom) } ?? "-"
        let potentialEDRHeadroom = screen.map { String(format: "%.2f", $0.potentialEDRHeadroom) } ?? "-"
        let message =
            "hdrPlaybackHitch q=\(context.quality.map(String.init) ?? "-")"
            + " range=\(context.dynamicRange)"
            + " fps=\(String(format: "%.1f", framesPerSecond))"
            + " avgMs=\(String(format: "%.1f", averageMilliseconds))"
            + " p95Ms=\(String(format: "%.1f", p95Milliseconds))"
            + " maxMs=\(String(format: "%.1f", maxMilliseconds))"
            + " hitches=\(hitchCount)"
            + " targetMs=\(String(format: "%.1f", targetSeconds * 1_000))"
            + " edr=\(edrHeadroom) potentialEDR=\(potentialEDRHeadroom)"
            + " thermal=\(thermalTitle(ProcessInfo.processInfo.thermalState))"
        PlayerMetricsLog.record(.playbackHitch, metricsID: context.metricsID, message: message)
        intervals.removeAll(keepingCapacity: true)
        // 以当前帧时间为新窗口起点，避免窗口漂移累积。
        windowStart = timestamp
    }

    private func expectedFrameDuration() -> Double {
        let maximumFramesPerSecond = activeScreen()?.maximumFramesPerSecond ?? 60
        return 1.0 / Double(max(maximumFramesPerSecond, 60))
    }

    private func activeScreen() -> UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen }
            .first
    }

    private func thermalTitle(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:
            return "nominal"
        case .fair:
            return "fair"
        case .serious:
            return "serious"
        case .critical:
            return "critical"
        @unknown default:
            return "unknown"
        }
    }
}
