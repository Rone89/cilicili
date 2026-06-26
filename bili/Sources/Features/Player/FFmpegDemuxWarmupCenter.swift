import Foundation
import Libavformat
import QuartzCore

actor FFmpegDemuxWarmupCenter {
    static let shared = FFmpegDemuxWarmupCenter()

    private let ttl: TimeInterval = 90
    private let maxCount = 12
    private var warmed: [String: Date] = [:]
    private var pending: [String: PendingWarmup] = [:]

    @discardableResult
    func warmLocalHLSMaster(_ url: URL, metricsID: String?) async -> Bool {
        guard url.scheme?.hasPrefix("http") == true else { return false }
        let key = url.absoluteString
        trimExpired()
        if warmed[key] != nil {
            await recordWarmup(
                state: "hit",
                timing: nil,
                metricsID: metricsID
            )
            return true
        }

        let warmup: PendingWarmup
        let state: String
        if let existing = pending[key] {
            warmup = existing
            state = "joined"
        } else {
            warmup = PendingWarmup(
                id: UUID(),
                task: Task.detached(priority: .utility) {
                    Self.openAndClose(url)
                }
            )
            pending[key] = warmup
            state = "ok"
        }

        let timing = await warmup.task.value
        if pending[key]?.id == warmup.id {
            finish(key: key, didWarm: timing.succeeded)
        }
        await recordWarmup(
            state: timing.succeeded ? state : "skip",
            timing: timing,
            metricsID: metricsID
        )
        return timing.succeeded
    }

    private func recordWarmup(state: String, timing: WarmupTiming?, metricsID: String?) async {
        guard let metricsID, !metricsID.isEmpty else { return }
        var parts = ["ffDemuxWarm=\(state)"]
        if let timing {
            parts.append("open=\(Self.formatMilliseconds(timing.openMilliseconds))")
            parts.append("find=\(Self.formatMilliseconds(timing.findMilliseconds))")
            parts.append("total=\(Self.formatMilliseconds(timing.totalMilliseconds))")
        }
        await PlayerMetricsLog.record(
            .manifestStage,
            metricsID: metricsID,
            message: parts.joined(separator: " ")
        )
    }

    private func finish(key: String, didWarm: Bool) {
        pending[key] = nil
        if didWarm {
            warmed[key] = Date()
            trimIfNeeded()
        }
    }

    private func trimExpired() {
        let expiry = Date().addingTimeInterval(-ttl)
        warmed = warmed.filter { $0.value >= expiry }
    }

    private func trimIfNeeded() {
        trimExpired()
        guard warmed.count > maxCount else { return }
        let kept = Set(
            warmed
                .sorted { $0.value > $1.value }
                .prefix(maxCount)
                .map(\.key)
        )
        warmed = warmed.filter { kept.contains($0.key) }
    }

    private nonisolated static func openAndClose(_ url: URL) -> WarmupTiming {
        let start = CACurrentMediaTime()
        var formatContext: UnsafeMutablePointer<AVFormatContext>? = avformat_alloc_context()
        formatContext?.pointee.flags |= AVFMT_FLAG_GENPTS
        formatContext?.pointee.probesize = 512 * 1024
        formatContext?.pointee.max_analyze_duration = 650_000

        let urlString = url.isFileURL ? url.path : url.absoluteString
        let openResult = avformat_open_input(&formatContext, urlString, nil, nil)
        let openMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: start)
        guard openResult == 0, formatContext != nil else {
            avformat_close_input(&formatContext)
            return WarmupTiming(
                succeeded: false,
                openMilliseconds: openMilliseconds,
                findMilliseconds: nil,
                totalMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: start)
            )
        }

        let findStart = CACurrentMediaTime()
        let findResult = avformat_find_stream_info(formatContext, nil)
        let findMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: findStart)
        avformat_close_input(&formatContext)
        return WarmupTiming(
            succeeded: findResult == 0,
            openMilliseconds: openMilliseconds,
            findMilliseconds: findMilliseconds,
            totalMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: start)
        )
    }

    private nonisolated static func formatMilliseconds(_ value: Double?) -> String {
        guard let value else { return "-" }
        return "\(Int(value.rounded()))ms"
    }

    private struct WarmupTiming: Sendable {
        let succeeded: Bool
        let openMilliseconds: Double
        let findMilliseconds: Double?
        let totalMilliseconds: Double
    }

    private struct PendingWarmup {
        let id: UUID
        let task: Task<WarmupTiming, Never>
    }
}
