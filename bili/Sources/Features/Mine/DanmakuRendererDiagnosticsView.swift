import SwiftUI
import UIKit

struct DanmakuRendererDiagnosticsView: View {
    @ObservedObject private var diagnostics = DanmakuRendererDiagnostics.shared
    @State private var copied = false

    var body: some View {
        Form {
            Section {
                LabeledContent("采集状态", value: diagnostics.isRecording ? "采集中" : "已停止")
                if let startedAt = diagnostics.startedAt {
                    LabeledContent(
                        "采集时长",
                        value: String(format: "%.0f 秒", Date().timeIntervalSince(startedAt))
                    )
                }
                Button {
                    if diagnostics.isRecording {
                        diagnostics.stop()
                    } else {
                        diagnostics.start()
                    }
                } label: {
                    Label(
                        diagnostics.isRecording ? "停止采集" : "开始采集",
                        systemImage: diagnostics.isRecording ? "stop.circle.fill" : "record.circle"
                    )
                }
                .accessibilityIdentifier("mine.danmakuDiagnostics.recording")
            } header: {
                Text("弹幕渲染采集")
            } footer: {
                Text("开始后返回视频页播放一段，再回到此页停止并复制。采集仅保存在本机内存中。")
            }

            #if DEBUG
            Section("Metal 实验") {
                let m = diagnostics.metalSummary
                LabeledContent("当前 Renderer", value: diagnostics.rendererType)
                LabeledContent("活跃 / 峰值 / glyph", value: "\(m.active) / \(m.peakActive) / \(m.glyphs)")
                LabeledContent("draw call / atlas 页数", value: "\(m.drawCalls) / \(m.pages)")
                LabeledContent("Atlas 使用 / 容量（像素）", value: "\(m.usedPixels) / \(m.capacityPixels)")
                LabeledContent("估算 FPS", value: m.medianFPS.map { String(format: "%.1f", $0) } ?? "—")
                LabeledContent("CPU 准备 / GPU 平均", value: "\(m.cpuAverageMs.map { String(format: "%.3fms", $0) } ?? "—") / \(m.gpuAverageMs.map { String(format: "%.3fms", $0) } ?? "—")")
                LabeledContent("GPU 忙跳帧 / 回调漏间隔", value: "\(m.skippedFrames) / \(m.callbackGaps)")
                LabeledContent("Atlas 拒绝的新 glyph", value: "\(m.rejectedGlyphs)")
                NavigationLink("本地密度与同步测试") { DanmakuRendererBenchmarkView() }
                Text("FPS 来自回调间隔，不是屏幕呈现测量。CPU / 功耗 / 全进程内存请用 Instruments 对比。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            #endif

            Section("DanmakuKit") {
                LabeledContent(
                    "自然入场 / 时间同步 / 迟到跳过",
                    value: "\(diagnostics.danmakuKitSummary.shootRequests) / \(diagnostics.danmakuKitSummary.syncRequests) / \(diagnostics.danmakuKitSummary.lateDrops)"
                )
                LabeledContent(
                    "活动弹幕 / 峰值",
                    value: "\(diagnostics.danmakuKitSummary.activeItems) / \(diagnostics.danmakuKitSummary.peakActiveItems)"
                )
                LabeledContent(
                    "Display Link 次数 / 估算 Hz / 漏间隔",
                    value: "\(diagnostics.danmakuKitSummary.displayLinkTicks) / \(String(format: "%.1f", diagnostics.danmakuKitSummary.medianDisplayLinkHz)) / \(diagnostics.danmakuKitSummary.displayLinkGapCount)"
                )
                LabeledContent(
                    "调度耗时样本 / 平均 / 最大",
                    value: "\(diagnostics.danmakuKitSummary.displayLinkWorkCount) / \(diagnostics.danmakuKitSummary.averageDisplayLinkWorkMilliseconds.map { String(format: "%.3f ms", $0) } ?? "—") / \(String(format: "%.3f ms", diagnostics.danmakuKitSummary.maxDisplayLinkWorkMilliseconds))"
                )
                LabeledContent(
                    "场景重建 / 最近原因",
                    value: "\(diagnostics.danmakuKitSummary.rebuilds) / \(diagnostics.danmakuKitSummary.lastRebuildReason)"
                )
                LabeledContent(
                    "文字绘制样本 / 平均 / 最大 / 超过 16.7ms",
                    value: "\(diagnostics.danmakuKitSummary.cellDrawCount) / \(diagnostics.danmakuKitSummary.averageCellDrawMilliseconds.map { String(format: "%.3f ms", $0) } ?? "—") / \(diagnostics.danmakuKitSummary.cellDrawCount == 0 ? "—" : String(format: "%.3f ms", diagnostics.danmakuKitSummary.maxCellDrawMilliseconds)) / \(diagnostics.danmakuKitSummary.delayedCellDrawCount)"
                )
                LabeledContent(
                    "表情图片加载成功 / 失败",
                    value: "\(diagnostics.danmakuKitSummary.emoteImageLoads) / \(diagnostics.danmakuKitSummary.emoteImageLoadFailures)"
                )
                Text("最近 40 条入场记录（ID 后 8 位、路径、入场年龄、触发来源、文字绘制耗时）会随诊断报告复制。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    UIPasteboard.general.string = diagnostics.makeReport()
                    copied = true
                } label: {
                    Label(copied ? "诊断数据已复制" : "一键复制诊断数据", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .accessibilityIdentifier("mine.danmakuDiagnostics.copy")
            } footer: {
                Text("刷新频率根据覆盖层 Display Link 回调估算；计时数据只反映当前埋点范围。")
            }
        }
        .navigationTitle("弹幕诊断")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                diagnostics.refresh()
            }
        }
        .onChange(of: diagnostics.revision) { _, _ in copied = false }
    }
}
