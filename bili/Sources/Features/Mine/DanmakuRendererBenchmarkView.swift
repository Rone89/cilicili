#if DEBUG
import SwiftUI
import UIKit

/// Local, copyright-free text fixture. The density override is DEBUG-only and
/// does not bypass any normal player's admission policy.
struct DanmakuRendererBenchmarkView: View {
    @StateObject private var diagnostics = DanmakuRendererDiagnostics()
    @State private var requestedFPS = 60
    @State private var viewport = CGSize.zero
    @State private var reports: [String] = []
    @State private var copied = false
    @State private var metal = false
    @State private var density = 50
    @State private var time: TimeInterval = 1
    @State private var playing = true
    @State private var rate = 1.0
    @State private var revision = 0
    private var settings: DanmakuSettings {
        DanmakuSettings(hidesInPortrait: false, danmakuKit: DanmakuKitRenderSettings(
            displayArea: .full, allowsDanmakuOverlap: true, fontScale: 1, fontWeight: .semibold,
            opacity: 0.92, enablesFloating: true, enablesTop: true, enablesBottom: true))
    }
    var body: some View {
        VStack {
            Toggle("Metal（关闭使用 DanmakuKit）", isOn: $metal)
                .accessibilityIdentifier("danmaku.benchmark.metal")
                .disabled(diagnostics.isRecording)
            Picker("活跃弹幕", selection: $density) {
                ForEach([10, 50, 100, 300, 600], id: \.self) { Text("\($0)").tag($0) }
            }.pickerStyle(.segmented)
                .accessibilityIdentifier("danmaku.benchmark.density")
                .disabled(diagnostics.isRecording)
            Picker("回调刷新率", selection: $requestedFPS) {
                Text("相同 60Hz").tag(60)
                Text("各自默认").tag(0)
            }.pickerStyle(.segmented)
                .disabled(diagnostics.isRecording)
                .accessibilityIdentifier("danmaku.benchmark.fps")
            BenchmarkOverlay(metal: metal, density: density, revision: revision,
                time: time, playing: playing, rate: rate, settings: settings,
                diagnostics: diagnostics, requestedFPS: requestedFPS == 0 ? nil : requestedFPS)
                .background(Color(white: 0.14))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                    if viewport != size, diagnostics.isRecording { finishCapture() }
                    viewport = size
                }
                .accessibilityIdentifier("danmaku.benchmark.surface")
            HStack {
                Button(playing ? "暂停" : "播放") { playing.toggle() }
                Button("后退") { time = max(0, time - 3) }
                Button("前进") { time = min(7, time + 3) }
                Button("重建") { time = 1; revision &+= 1 }
                Picker("倍速", selection: $rate) {
                    ForEach([1.0, 1.5, 2.0], id: \.self) { Text("\($0, specifier: "%.1f")x").tag($0) }
                }.pickerStyle(.menu)
            }
            .disabled(diagnostics.isRecording)
            Text("采样 Kit=\(diagnostics.danmakuKitSummary.displayLinkTicks) Metal=\(diagnostics.metalSummary.frames) · 活跃/峰值 \(metal ? diagnostics.metalSummary.active : diagnostics.danmakuKitSummary.activeItems)/\(metal ? diagnostics.metalSummary.peakActive : diagnostics.danmakuKitSummary.peakActiveItems)")
                .font(.caption.monospacedDigit())
                .accessibilityIdentifier("danmaku.benchmark.samples")
            HStack {
                Button(diagnostics.isRecording ? "停止采集" : "开始独立采集") {
                    if diagnostics.isRecording { finishCapture() } else { startCapture() }
                }.accessibilityIdentifier("danmaku.benchmark.capture")
                Button(copied ? "已复制" : "复制报告（\(reports.count)份）") {
                    UIPasteboard.general.string = reports.joined(separator: "\n\n")
                    copied = true
                }.disabled(reports.isEmpty || diagnostics.isRecording)
                    .accessibilityIdentifier("danmaku.benchmark.copy")
            }
            Text("\(time, specifier: "%.2f")s · 固定文字 / 相同输入 · 显示区域允许重叠，仅用于压力测试。")
                .font(.caption)
            Text("采集锁定配置；每轮自动从 7s 回到 1s。默认模式：Kit 60Hz，Metal 请求屏幕最高刷新率。回调 Hz 不等于呈现 FPS；需用 Instruments 比较 CPU / 功耗。")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle("弹幕本地 A/B")
        .task {
            var previous = CACurrentMediaTime()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                let now = CACurrentMediaTime()
                if playing {
                    time += (now - previous) * rate
                    if time > 7 { time = 1; revision &+= 1 }
                }
                previous = now
            }
        }
        .onDisappear { if diagnostics.isRecording { finishCapture() } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            if diagnostics.isRecording { finishCapture() }
        }
        .onChange(of: density) { _, _ in time = 1; revision &+= 1 }
    }

    private func startCapture() {
        guard viewport.width > 0, viewport.height > 0 else { return }
        copied = false
        playing = true
        time = 1
        revision &+= 1
        diagnostics.startBenchmark(.init(renderer: metal ? "Metal" : "DanmakuKit", density: density,
            requestedFPS: requestedFPS == 0 ? nil : requestedFPS, playbackRate: rate, viewport: viewport))
    }

    private func finishCapture() {
        diagnostics.stop()
        reports.append(diagnostics.makeReport())
        if reports.count > 10 { reports.removeFirst() }
        copied = false
    }
}

private struct BenchmarkOverlay: UIViewRepresentable {
    let metal: Bool
    let density: Int
    let revision: Int
    let time: TimeInterval
    let playing: Bool
    let rate: Double
    let settings: DanmakuSettings
    let diagnostics: DanmakuRendererDiagnostics
    let requestedFPS: Int?

    func makeUIView(context: Context) -> DanmakuRendererHostView { DanmakuRendererHostView(frame: .zero) }
    func updateUIView(_ view: DanmakuRendererHostView, context: Context) {
        view.debugDiagnostics = diagnostics
        view.debugPreferredFramesPerSecond = requestedFPS
        view.debugMaximumActiveCount = density
        view.selectRenderer(metalEnabled: metal)
        let items = (0..<density).map { index in
            DanmakuItem(id: "benchmark-\(revision)-\(index)", time: 0,
                mode: index % 10 == 0 ? 5 : (index % 10 == 1 ? 4 : 1),
                fontSize: 25, color: index % 3 == 0 ? 0x55D6FF : 0xFFFFFF,
                text: "弹幕 \(index) · Metal ABC 123！")
        }
        view.apply(configuration: DanmakuOverlayConfiguration(items: items,
            itemsRevision: revision, currentTime: time, isPlaying: playing, playbackRate: rate,
            isEnabled: true, hasPresentedPlayback: true, isLoadShedding: false,
            settings: settings, topInset: 0, bottomInset: 0))
    }
    static func dismantleUIView(_ view: DanmakuRendererHostView, coordinator: ()) { view.stop() }
}
#endif
