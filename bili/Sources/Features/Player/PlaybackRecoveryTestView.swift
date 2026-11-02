import SwiftUI
import UIKit

struct PlaybackRecoveryTestView: View {
    @ObservedObject private var player: PlayerStateViewModel
    @ObservedObject private var runner: PlaybackRecoveryTestRunner
    @StateObject private var reports = PlaybackRecoveryTestReportStore.shared

    init(player: PlayerStateViewModel) {
        self.player = player
        runner = player.recoveryTestRunner
    }

    var body: some View {
        List {
            Section {
                Text("自动执行暂停、恢复、进度跳转和快速暂停／播放，共33次，约12分钟。请保持App前台；测试期间会保持屏幕常亮，并改变当前播放进度。结束后暂停播放。")
                Text("暂停边界短测只执行新增情景3次，通常约1分钟，准备或停用超时会延长。可随时停止；新测试会替换上一轮报告。")
                    .foregroundStyle(.secondary)
            }

            Section {
                if runner.isRunning {
                    Text(runner.progressText)
                        .accessibilityIdentifier("recovery.test.progress")
                    if runner.secondsRemaining > 0 {
                        Text("剩余约\(runner.secondsRemaining)秒")
                            .monospacedDigit()
                    }
                    Button("停止测试", role: .destructive) { runner.cancel() }
                        .accessibilityIdentifier("recovery.test.stop")
                } else {
                    if let message = runner.readinessMessage {
                        Text(message).foregroundStyle(.secondary)
                    }
                    Button("暂停边界短测（3次）") { runner.start(onlyPauseBoundary: true) }
                        .disabled(runner.readinessMessage != nil)
                        .accessibilityIdentifier("recovery.test.startBoundary")
                    Button(runner.report == nil ? "开始自动测试" : "重新开始自动测试") { runner.start() }
                        .disabled(runner.readinessMessage != nil)
                        .accessibilityIdentifier("recovery.test.start")
                }
            }

            if !runner.isRunning, let report = runner.report {
                PlaybackRecoveryTestReportSection(report: report, persistenceError: reports.persistenceError)
            }
        }
        .navigationTitle("自动恢复测试")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { runner.cancel(reason: "离开自动测试页") }
    }
}

struct PlaybackRecoveryTestSavedReportView: View {
    @StateObject private var store = PlaybackRecoveryTestReportStore.shared

    var body: some View {
        List {
            if let report = store.report {
                PlaybackRecoveryTestReportSection(report: report, persistenceError: store.persistenceError)
            } else {
                Text(store.persistenceError ?? "暂无报告。打开一个至少5分钟的视频，在“更多播放设置”中进入“自动恢复测试”。")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("自动恢复测试报告")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PlaybackRecoveryTestReportSection: View {
    let report: PlaybackRecoveryTestReport
    let persistenceError: String?
    @State private var didCopy = false

    var body: some View {
        Section("测试报告") {
            Text(statusText)
                .accessibilityIdentifier("recovery.test.result")
            Text("已采集 \(observedCount)/\(report.plannedTrialCount) 项；其余项目请以报告中的超时、中断或缺失数据标记为准。")
            if let reason = report.reason { Text(reason).foregroundStyle(.secondary) }
            if let persistenceError {
                Text(persistenceError).foregroundStyle(.orange)
            }
            Button {
                UIPasteboard.general.string = report.exportText
                didCopy = true
            } label: {
                Label(didCopy ? "已复制测试报告" : "复制测试报告",
                      systemImage: didCopy ? "checkmark" : "doc.on.doc")
            }
            .accessibilityIdentifier("recovery.test.copy")
            ShareLink(item: report.exportText) {
                Label("分享测试报告", systemImage: "square.and.arrow.up")
            }
            Text("自动测试记录恢复数据，不代替画面、声音或触摸手势的人工验收。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var observedCount: Int { report.trials.filter { $0.outcome == "observed" }.count }

    private var statusText: String {
        switch report.status {
        case "completed": "测试结束"
        case "running": "测试正在进行，当前为部分数据"
        case "failed": "测试遇到异常，已保留部分数据"
        default: "测试已中断，已保留部分数据"
        }
    }
}
