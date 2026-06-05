import Foundation
import SwiftUI

struct PlaybackNetworkPlayerSection: View {
    @ObservedObject var playerViewModel: PlayerStateViewModel
    let fallbackMessage: String?

    var body: some View {
        Section("播放器") {
            diagnosticRow("状态", playerStateTitle)
            diagnosticRow("阶段", playerViewModel.playbackPhase.diagnosticTitle)
            diagnosticRow("引擎", playerViewModel.engineDiagnostics.engineName)
            diagnosticRow("解码", playerViewModel.engineDiagnostics.decodePath.title)
            diagnosticRow("异步硬解", playerViewModel.engineDiagnostics.asynchronousDecompressionEnabled ? "开启" : "关闭")
            if playerViewModel.engineDiagnostics.hlsVideoVariantCount > 0 {
                diagnosticRow("HLS 档位", hlsVariantText(playerViewModel.engineDiagnostics))
            }
            diagnosticRow("首帧", playerViewModel.hasPresentedPlayback ? "已显示" : "等待中")
            diagnosticRow("缓冲", playerViewModel.isBuffering ? "缓冲中" : "未缓冲")
            diagnosticRow("可拖动", playerViewModel.canSeek ? "可用" : "等待就绪")
            diagnosticRow("恢复次数", "\(playerViewModel.recoveryAttemptCount)")
            diagnosticRow("准备耗时", formattedMilliseconds(playerViewModel.prepareElapsedMilliseconds))
            diagnosticRow("首帧耗时", formattedMilliseconds(playerViewModel.firstFrameElapsedMilliseconds))
            diagnosticRow("缓冲次数", "\(playerViewModel.bufferingCount)")
            diagnosticRow("最近缓冲", formattedMilliseconds(playerViewModel.lastBufferingElapsedMilliseconds))

            let loadingProgress = min(max(playerViewModel.loadingProgress, 0), 1)
            diagnosticRow("加载进度", "\(Int((loadingProgress * 100).rounded()))%")

            if let forwardBuffer = playerViewModel.engineDiagnostics.preferredForwardBufferDuration {
                diagnosticRow("前向缓冲", String(format: "%.2fs", forwardBuffer))
            }

            if let errorMessage = playerViewModel.errorMessage, !errorMessage.isEmpty {
                diagnosticMultilineRow("错误", errorMessage)
            }

            if let fallbackMessage, !fallbackMessage.isEmpty {
                diagnosticMultilineRow("降级信息", fallbackMessage)
            }
        }
    }

    private var playerStateTitle: String {
        if let errorMessage = playerViewModel.errorMessage, !errorMessage.isEmpty {
            return "播放错误"
        }
        if playerViewModel.isPreparing {
            return "准备中"
        }
        if playerViewModel.isBuffering {
            return "缓冲中"
        }
        if playerViewModel.isPlaying {
            return "播放中"
        }
        return "暂停/待播"
    }

    private func diagnosticRow(_ title: String, _ value: String) -> some View {
        LabeledContent {
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        } label: {
            Text(title)
        }
    }

    private func diagnosticMultilineRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formattedMilliseconds(_ value: Int?) -> String {
        guard let value else { return "未记录" }
        if value >= 1000 {
            return String(format: "%.2f s", Double(value) / 1000)
        }
        return "\(value) ms"
    }

    private func hlsVariantText(_ diagnostics: PlayerEngineDiagnostics) -> String {
        let count = diagnostics.hlsVideoVariantCount
        let qualities = diagnostics.hlsVideoVariantQualities
            .map { "q\($0)" }
            .joined(separator: "/")
        guard !qualities.isEmpty else { return "\(count) 档" }
        return "\(count) 档 · \(qualities)"
    }
}
