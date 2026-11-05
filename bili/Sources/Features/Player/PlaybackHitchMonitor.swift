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
    private var longGapCount = 0
    private var currentTargetSeconds: CFTimeInterval = 1.0 / 60.0
    private var ownerID: ObjectIdentifier?
    private var context: Context?

    private override init() {
        super.init()
    }

    func start(owner: AnyObject, metricsID: String, quality: Int?, dynamicRange: BiliVideoDynamicRange) {
        let nextContext = Context(
            metricsID: metricsID,
            quality: quality,
            dynamicRange: dynamicRange.rawValue
        )
        let nextOwnerID = ObjectIdentifier(owner)
        if displayLink != nil {
            // 清晰度切换时旧播放器可能晚于新播放器执行 teardown；所有权移交到新播放器，
            // 避免旧会话的 stop(owner:) 误停新会话。
            if ownerID != nextOwnerID {
                ownerID = nextOwnerID
                context = nextContext
                resetWindow(at: CACurrentMediaTime())
            } else {
                context = nextContext
            }
            return
        }
        ownerID = nextOwnerID
        context = nextContext
        windowStart = CACurrentMediaTime()
        lastTimestamp = nil
        intervals.removeAll(keepingCapacity: true)
        longGapCount = 0
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop(owner: AnyObject) {
        guard ownerID == ObjectIdentifier(owner) else { return }
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = nil
        windowStart = 0
        intervals.removeAll(keepingCapacity: false)
        longGapCount = 0
        ownerID = nil
        context = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        let timestamp = link.timestamp
        // ProMotion 会按内容把刷新率降到 48/40/30Hz；用系统给出的下一帧预期间隔
        // 作为基准，避免把正常降频误判为掉帧。
        currentTargetSeconds = max(link.targetTimestamp - link.timestamp, 0.001)
        // 应用不在前台时（切后台、来电、控制中心）会产生超长间隔，不能算作掉帧。
        guard UIApplication.shared.applicationState == .active else {
            resetWindow(at: timestamp)
            return
        }
        if let lastTimestamp {
            let interval = timestamp - lastTimestamp
            // 超过 0.5s 的间隔视为窗口外断裂（切页面/系统弹层），单列统计。
            if interval > 0.5 {
                longGapCount += 1
            } else {
                intervals.append(interval)
            }
        }
        lastTimestamp = timestamp
        guard timestamp - windowStart >= windowDuration else { return }
        guard !intervals.isEmpty || longGapCount > 0 else {
            resetWindow(at: timestamp)
            return
        }
        publish(at: timestamp)
    }

    private func resetWindow(at timestamp: CFTimeInterval) {
        lastTimestamp = nil
        windowStart = timestamp
        intervals.removeAll(keepingCapacity: true)
        longGapCount = 0
    }

    private func publish(at timestamp: CFTimeInterval) {
        guard let context else { return }
        let sorted = intervals.sorted()
        let count = sorted.count
        let averageMilliseconds = count > 0 ? sorted.reduce(0, +) / Double(count) * 1_000 : 0
        let p95Milliseconds = count > 0 ? sorted[min(count - 1, Int(Double(count) * 0.95))] * 1_000 : 0
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
            + " frames=\(count)"
            + " longGaps=\(longGapCount)"
            + " avgMs=\(String(format: "%.1f", averageMilliseconds))"
            + " p95Ms=\(String(format: "%.1f", p95Milliseconds))"
            + " maxMs=\(String(format: "%.1f", maxMilliseconds))"
            + " hitches=\(hitchCount)"
            + " targetMs=\(String(format: "%.1f", targetSeconds * 1_000))"
            + " edr=\(edrHeadroom) potentialEDR=\(potentialEDRHeadroom)"
            + " thermal=\(thermalTitle(ProcessInfo.processInfo.thermalState))"
        PlayerMetricsLog.record(.playbackHitch, metricsID: context.metricsID, message: message)
        resetWindow(at: timestamp)
    }

    private func expectedFrameDuration() -> Double {
        if currentTargetSeconds > 0.001 {
            return currentTargetSeconds
        }
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
