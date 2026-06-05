import Foundation
import SwiftUI

struct VideoDetailPerformanceOverlayContainer: View {
    @ObservedObject var store: VideoDetailNetworkDiagnosticsRenderStore

    var body: some View {
        PlayerPerformanceOverlay(
            metricsID: store.metricsID,
            playerViewModel: store.playerViewModel
        )
    }
}

struct PlayerPerformanceOverlay: View {
    @StateObject private var sessionObserver: PlayerPerformanceSessionObserver
    let metricsID: String
    let playerViewModel: PlayerStateViewModel?

    init(metricsID: String, playerViewModel: PlayerStateViewModel?) {
        self.metricsID = metricsID
        self.playerViewModel = playerViewModel
        _sessionObserver = StateObject(
            wrappedValue: PlayerPerformanceSessionObserver(metricsID: metricsID)
        )
    }

    private var session: PlayerPerformanceSession? {
        sessionObserver.session
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg.rectangle")
                    .font(.caption2.weight(.bold))
                Text("播放性能")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 8)
                Text(shortID)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            if let session {
                metricsGrid(session)
                startupWaterfall(session)
                diagnosticsMessages(session)
                playbackCounters(session)
                terminalMessages(session)
            } else {
                Text("等待播放事件")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(width: 226, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.20), lineWidth: 0.6)
        }
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .onChange(of: metricsID) { _, metricsID in
            sessionObserver.updateContext(metricsID: metricsID)
        }
    }

    private var shortID: String {
        guard metricsID.count > 8 else { return metricsID }
        return String(metricsID.suffix(8))
    }

    private func metricsGrid(_ session: PlayerPerformanceSession) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.fixed(74), spacing: 8),
                GridItem(.fixed(74), spacing: 8)
            ],
            alignment: .leading,
            spacing: 6
        ) {
            metric("总首帧", session.firstFrameTotalMilliseconds)
            metric("播放器", session.firstFramePlayerMilliseconds)
            metric("Detail", session.detailLoadMilliseconds)
            metric("取流", session.playURLMilliseconds)
            metric("Prepare", session.prepareMilliseconds)
            metric("续播", session.resumeApplyMilliseconds)
            metric("续验", session.lastResumeRecoveryMilliseconds)
        }
    }

    @ViewBuilder
    private func diagnosticsMessages(_ session: PlayerPerformanceSession) -> some View {
        if let detailSource = session.detailSourceMessage {
            Label(detailSource, systemImage: "doc.text.magnifyingglass")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }

        if let diagnostics = playerViewModel?.engineDiagnostics {
            Text(diagnostics.compactDescription)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }

        if let cdnHost = session.cdnHostMessage {
            Label(cdnHost, systemImage: "network")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }

        if let networkMessage = session.networkMessage {
            Text(networkMessage)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }

        if let accessLogMessage = session.accessLogMessage {
            Text(accessLogMessage)
                .font(.caption2.monospacedDigit())
                .foregroundStyle((session.accessLogStallCount ?? 0) > 0 ? .orange : .secondary)
                .lineLimit(1)
        }

        if let mediaCacheMessage = session.mediaCacheMessage {
            Text(mediaCacheMessage)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }

        if let manifestStageMessage = session.manifestStageMessage {
            Text(manifestStageMessage)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }

        if let resumeDecisionMessage = session.resumeDecisionMessage {
            Label(resumeDecisionMessage, systemImage: "clock.arrow.circlepath")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }

        if let resumeRecoveryMessage = session.resumeRecoveryMessage {
            Label(resumeRecoveryMessage, systemImage: "checkmark.circle")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(session.resumeRecoverySlowCount > 0 ? .orange : .secondary)
                .lineLimit(2)
        }

        if let seekMessage = session.seekMessage {
            Label(seekMessage, systemImage: "forward.frame")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }

        if let seekRecoveryMessage = session.seekRecoveryMessage {
            Label(seekRecoveryMessage, systemImage: "speedometer")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(session.seekRecoverySlowCount > 0 ? .orange : .secondary)
                .lineLimit(2)
        }

        if let speedBoostMessage = session.speedBoostMessage {
            Label(speedBoostMessage, systemImage: "forward.fill")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(session.speedBoostInterruptionCount > 0 ? .orange : .secondary)
                .lineLimit(2)
        }

        if let startupBreakdownMessage = session.startupBreakdownMessage {
            Label(startupBreakdownMessage, systemImage: "chart.bar.xaxis")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }

        if let prepareStageMessage = session.prepareStageMessage {
            prepareStages(prepareStageMessage)
        }

        if let startupGapMessage = session.startupGapMessage {
            startupGaps(startupGapMessage)
        }
    }

    private func prepareStages(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Prepare stages")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 6),
                    GridItem(.flexible(), spacing: 6)
                ],
                alignment: .leading,
                spacing: 4
            ) {
                ForEach(prepareStageMetrics(from: message), id: \.name) { stage in
                    prepareStageMetric(stage)
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    @ViewBuilder
    private func startupWaterfall(_ session: PlayerPerformanceSession) -> some View {
        let stages = startupWaterfallStages(for: session)
        if !stages.isEmpty {
            let maxMilliseconds = max(stages.map(\.milliseconds).max() ?? 1, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text("First frame")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(stages) { stage in
                    HStack(spacing: 5) {
                        Text(stage.title)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(width: 48, alignment: .leading)

                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.secondary.opacity(0.13))
                                .frame(width: 70, height: 5)

                            Capsule()
                                .fill(metricColor(stage.milliseconds).opacity(0.88))
                                .frame(
                                    width: startupWaterfallBarWidth(
                                        milliseconds: stage.milliseconds,
                                        maxMilliseconds: maxMilliseconds
                                    ),
                                    height: 5
                                )
                        }

                        Spacer(minLength: 2)

                        Text(millisecondsText(stage.milliseconds))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(metricColor(stage.milliseconds))
                            .lineLimit(1)
                            .frame(width: 43, alignment: .trailing)
                    }
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }

    private func startupGaps(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Startup gaps")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(message)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func playbackCounters(_ session: PlayerPerformanceSession) -> some View {
        HStack(spacing: 8) {
            Text("缓冲 \(session.bufferCount)")
            if session.resumeRecoveryCount > 0 {
                Text("续验 \(session.resumeRecoveryCount)")
            }
            Text("Seek \(session.seekCount)")
            if session.seekRecoveryCount > 0 {
                Text("恢复 \(session.seekRecoveryCount)")
            }
            if session.speedBoostCount > 0 {
                Text("倍速 \(session.speedBoostCount)")
            }
            if session.speedBoostInterruptionCount > 0 {
                Text("中断 \(session.speedBoostInterruptionCount)")
            }
            if let quality = session.selectedQualityMessage {
                Text(quality)
                    .lineLimit(1)
            }
        }
        .font(.caption2)
        .foregroundStyle(counterColor(for: session))
    }

    @ViewBuilder
    private func terminalMessages(_ session: PlayerPerformanceSession) -> some View {
        if let qualitySupplementMessage = session.qualitySupplementMessage {
            Text(qualitySupplementMessage)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.orange)
                .lineLimit(2)
        }

        if let failure = session.failureMessage {
            Text(failure)
                .font(.caption2)
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }

    private func metric(_ title: String, _ milliseconds: Int?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(millisecondsText(milliseconds))
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(metricColor(milliseconds))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func prepareStageMetric(_ stage: PrepareStageMetric) -> some View {
        HStack(spacing: 3) {
            Text(stage.name)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 2)

            Text(stage.value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(metricColor(stage.milliseconds))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func prepareStageMetrics(from message: String) -> [PrepareStageMetric] {
        let metrics = message
            .split(separator: " ")
            .compactMap { token -> PrepareStageMetric? in
                let parts = token.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { return nil }
                return PrepareStageMetric(
                    name: String(parts[0]),
                    value: String(parts[1])
                )
            }
        return metrics.isEmpty
            ? [PrepareStageMetric(name: "prepare", value: message)]
            : metrics
    }

    private func startupWaterfallStages(for session: PlayerPerformanceSession) -> [StartupWaterfallStage] {
        var stages: [StartupWaterfallStage] = []
        appendStartupStage(&stages, id: "open-detail", title: "打开", start: session.openedAt, end: session.detailStartedAt)
        appendStartupStage(&stages, id: "detail-url", title: "详情", start: session.detailStartedAt, end: session.playURLStartedAt)
        appendStartupStage(&stages, id: "url-load", title: "取流", start: session.playURLStartedAt, end: session.playURLLoadedAt)
        appendStartupStage(&stages, id: "player", title: "建播放器", start: session.playURLLoadedAt, end: session.playerCreatedAt)
        appendStartupStage(&stages, id: "prepare", title: "准备", start: session.prepareStartedAt, end: session.prepareReturnedAt)
        appendStartupStage(&stages, id: "first-frame", title: "首帧", start: session.playRequestedAt, end: session.firstFrameAt)
        return stages
    }

    private func appendStartupStage(
        _ stages: inout [StartupWaterfallStage],
        id: String,
        title: String,
        start: Date?,
        end: Date?
    ) {
        guard let start, let end else { return }
        stages.append(StartupWaterfallStage(id: id, title: title, start: start, end: end))
    }

    private func startupWaterfallBarWidth(milliseconds: Int, maxMilliseconds: Int) -> CGFloat {
        let ratio = CGFloat(milliseconds) / CGFloat(max(maxMilliseconds, 1))
        return max(4, min(70, ratio * 70))
    }

    private func millisecondsText(_ value: Int?) -> String {
        guard let value else { return "-" }
        if value >= 1000 {
            return String(format: "%.2fs", Double(value) / 1000)
        }
        return "\(value)ms"
    }

    private func metricColor(_ value: Int?) -> Color {
        guard let value else { return .secondary }
        if value >= 2500 {
            return .red
        }
        if value >= 1400 {
            return .orange
        }
        return .green
    }

    private func counterColor(for session: PlayerPerformanceSession) -> Color {
        (session.bufferCount > 0
            || session.speedBoostInterruptionCount > 0
            || session.resumeRecoverySlowCount > 0
            || session.seekRecoverySlowCount > 0)
            ? .orange
            : .secondary
    }
}

private struct PrepareStageMetric: Hashable {
    let name: String
    let value: String

    var milliseconds: Int? {
        let numericText = value
            .replacingOccurrences(of: "ms", with: "")
            .replacingOccurrences(of: "s", with: "")
        guard let number = Double(numericText) else { return nil }
        return value.hasSuffix("s")
            ? Int((number * 1000).rounded())
            : Int(number.rounded())
    }
}

private struct StartupWaterfallStage: Identifiable, Hashable {
    let id: String
    let title: String
    let start: Date
    let end: Date

    var milliseconds: Int {
        max(Int((end.timeIntervalSince(start) * 1000).rounded()), 0)
    }
}
