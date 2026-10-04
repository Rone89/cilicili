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
    @State private var automaticRunID: UUID?
    @State private var automaticPlan = DanmakuBenchmarkPlan()
    @State private var automaticStep = 0
    @State private var automaticPhase = ""
    @State private var automaticDeadline: CFTimeInterval = 0
    @State private var sampleSeconds = 90.0
    @State private var automaticReports: [String] = []
    @State private var savedReportURL: URL?
    @State private var saveError: String?
    @State private var previousIdleTimerDisabled: Bool?
    private var configurationLocked: Bool { diagnostics.isRecording || automaticRunID != nil }
    private var settings: DanmakuSettings {
        DanmakuSettings(hidesInPortrait: false, danmakuKit: DanmakuKitRenderSettings(
            displayArea: .full, allowsDanmakuOverlap: true, fontScale: 1, fontWeight: .semibold,
            opacity: 0.92, enablesFloating: true, enablesTop: true, enablesBottom: true))
    }
    var body: some View {
        VStack {
            Toggle("Metal（关闭使用 DanmakuKit）", isOn: $metal)
                .accessibilityIdentifier("danmaku.benchmark.metal")
                .disabled(configurationLocked)
            Picker("活跃弹幕", selection: $density) {
                ForEach([10, 50, 100, 300, 600], id: \.self) { Text("\($0)").tag($0) }
            }.pickerStyle(.segmented)
                .accessibilityIdentifier("danmaku.benchmark.density")
                .disabled(configurationLocked)
            Picker("回调刷新率", selection: $requestedFPS) {
                Text("相同 60Hz").tag(60)
                Text("各自默认").tag(0)
            }.pickerStyle(.segmented)
                .disabled(configurationLocked)
                .accessibilityIdentifier("danmaku.benchmark.fps")
            BenchmarkOverlay(metal: metal, density: density, revision: revision,
                time: time, playing: playing, rate: rate, settings: settings,
                diagnostics: diagnostics, requestedFPS: requestedFPS == 0 ? nil : requestedFPS)
                .background(Color(white: 0.14))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                    if viewport != size {
                        if automaticRunID != nil { stopAutomatic(reason: "viewportChanged") }
                        else if diagnostics.isRecording { finishCapture() }
                    }
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
            .disabled(configurationLocked)
            Text("采样 Kit=\(diagnostics.danmakuKitSummary.displayLinkTicks) Metal=\(diagnostics.metalSummary.frames) · 活跃/峰值 \(metal ? diagnostics.metalSummary.active : diagnostics.danmakuKitSummary.activeItems)/\(metal ? diagnostics.metalSummary.peakActive : diagnostics.danmakuKitSummary.peakActiveItems)")
                .font(.caption.monospacedDigit())
                .accessibilityIdentifier("danmaku.benchmark.samples")
            HStack {
                Button(diagnostics.isRecording ? "停止采集" : "开始独立采集") {
                    if diagnostics.isRecording { finishCapture() } else { startCapture() }
                }.accessibilityIdentifier("danmaku.benchmark.capture")
                    .disabled(automaticRunID != nil)
                Button(copied ? "已复制" : "复制报告（\(reports.count)份）") {
                    UIPasteboard.general.string = reports.joined(separator: "\n\n")
                    copied = true
                }.disabled(reports.isEmpty || configurationLocked)
                    .accessibilityIdentifier("danmaku.benchmark.copy")
            }
            HStack {
                Picker("每轮时长", selection: $sampleSeconds) {
                    Text("短测 15s").tag(15.0)
                    Text("标准 90s").tag(90.0)
                }.pickerStyle(.menu).disabled(configurationLocked)
                Button(automaticRunID == nil ? "一键自动 A/B" : "停止自动测试") {
                    if automaticRunID == nil { beginAutomatic() }
                    else { stopAutomatic(reason: "userStopped") }
                }.disabled(diagnostics.isRecording && automaticRunID == nil)
                    .accessibilityIdentifier("danmaku.benchmark.automatic")
                if let savedReportURL {
                    ShareLink(item: savedReportURL) { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("分享自动测试报告")
                        .disabled(automaticRunID != nil)
                }
            }
            Text(automaticProgress)
                .font(.caption.monospacedDigit()).lineLimit(1)
                .accessibilityIdentifier("danmaku.benchmark.progress")
            Text("自动测试固定 60Hz / 1x，每轮预热 3s；报告自动保存，可分享。退出或退到后台会中止。")
                .font(.caption2).foregroundStyle(.secondary)
            if let saveError { Text(saveError).font(.caption).foregroundStyle(.red) }
            Text("\(time, specifier: "%.2f")s · 固定文字 / 相同输入 · 显示区域允许重叠，仅用于压力测试。")
                .font(.caption)
            Text("采集锁定配置；每轮自动从 7s 回到 1s。默认模式：Kit 60Hz，Metal 请求屏幕最高刷新率。回调 Hz 不等于呈现 FPS；需用 Instruments 比较 CPU / 功耗。")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle("弹幕本地 A/B")
        .task {
            restoreSavedReportURL()
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
        .task(id: automaticRunID) {
            guard let id = automaticRunID else { return }
            await runAutomatic(id: id)
        }
        .onDisappear { stopAll(reason: "pageExited") }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            stopAll(reason: "appInactive")
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

    private func finishCapture(header: String? = nil) {
        guard diagnostics.isRecording else { return }
        diagnostics.stop()
        let report = (header.map { $0 + "\n" } ?? "") + diagnostics.makeReport()
        reports.append(report)
        if reports.count > 50 { reports.removeFirst() }
        if header != nil { automaticReports.append(report) }
        copied = false
    }

    private var automaticProgress: String {
        guard automaticRunID != nil else {
            return automaticPhase.isEmpty ? "自动：50/100/300 条 × ABBA；约 \(Int(DanmakuBenchmarkPlan(sampleSeconds: sampleSeconds).totalSeconds / 60)) 分钟" : automaticPhase
        }
        let remaining = max(0, Int(ceil(automaticDeadline - CACurrentMediaTime())))
        return "\(automaticStep + 1)/\(automaticPlan.steps.count) · \(automaticPhase) · 剩余 \(remaining)s"
    }

    private func beginAutomatic() {
        guard !configurationLocked, viewport.width > 0, viewport.height > 0 else { return }
        automaticPlan = DanmakuBenchmarkPlan(sampleSeconds: sampleSeconds)
        // Short runtime coverage is only available inside the existing UI-test fixture.
        let args = ProcessInfo.processInfo.arguments
        if args.contains("danmakuBenchmark"), args.contains("--danmaku-auto-test-short") {
            automaticPlan = DanmakuBenchmarkPlan(sampleSeconds: 1, warmupSeconds: 0.5, densities: [10])
        }
        automaticStep = 0
        automaticReports = []
        savedReportURL = nil
        saveError = nil
        automaticPhase = "准备"
        requestedFPS = 60
        rate = 1
        previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        automaticRunID = UUID()
    }

    @MainActor
    private func runAutomatic(id: UUID) async {
        let plan = automaticPlan
        do {
            for (index, step) in plan.steps.enumerated() {
                try Task.checkCancellation()
                guard automaticRunID == id else { return }
                automaticStep = index
                metal = step.metal
                density = step.density
                playing = true
                time = 1
                revision &+= 1
                automaticPhase = "\(step.renderer) \(step.density) 条 · 预热"
                automaticDeadline = CACurrentMediaTime() + plan.warmupSeconds
                try await Task.sleep(for: .seconds(plan.warmupSeconds))
                try Task.checkCancellation()
                guard automaticRunID == id else { return }
                startCapture()
                automaticPhase = "\(step.renderer) \(step.density) 条 · 采集"
                automaticDeadline = CACurrentMediaTime() + plan.sampleSeconds
                try await Task.sleep(for: .seconds(plan.sampleSeconds))
                try Task.checkCancellation()
                guard automaticRunID == id else { return }
                let hasFrames = step.metal ? diagnostics.metalSummary.automaticFrames > 0
                    : diagnostics.danmakuKitSummary.displayLinkTicks > 0
                guard diagnostics.rendererType == step.renderer, hasFrames else {
                    stopAutomatic(reason: "rendererUnavailableOrNoFrames")
                    return
                }
                finishCapture(header: plan.reportHeader(suiteID: id, index: index, status: "completed"))
                saveAutomaticReport(id: id, status: index == plan.steps.count - 1 ? "completed" : "running")
            }
            automaticRunID = nil
            playing = false
            restoreIdleTimer()
            automaticPhase = "自动测试完成 · \(plan.steps.count) 份报告"
        } catch {
            // The stopping path saves a partial capture before invalidating the run ID.
            if automaticRunID == id { stopAutomatic(reason: "taskCancelled") }
        }
    }

    private func stopAll(reason: String) {
        if automaticRunID != nil { stopAutomatic(reason: reason) }
        else if diagnostics.isRecording { finishCapture() }
    }

    private func stopAutomatic(reason: String) {
        guard let id = automaticRunID else { return }
        finishCapture(header: automaticPlan.reportHeader(suiteID: id, index: automaticStep, status: "interrupted:\(reason)"))
        saveAutomaticReport(id: id, status: "interrupted:\(reason)")
        automaticRunID = nil
        playing = false
        restoreIdleTimer()
        automaticPhase = "已停止 · \(automaticReports.count) 份报告"
    }

    private func restoreIdleTimer() {
        if let previousIdleTimerDisabled {
            UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
            self.previousIdleTimerDisabled = nil
        }
    }

    private func saveAutomaticReport(id: UUID, status: String) {
        do {
            let directory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true).appendingPathComponent("DanmakuBenchmarks", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("AB-\(id.uuidString).txt")
            let text = "Automatic suite status: \(status)\n" + automaticReports.joined(separator: "\n\n")
            try text.write(to: url, atomically: true, encoding: .utf8)
            savedReportURL = url
            saveError = nil
        } catch {
            saveError = "报告文件保存失败，可用复制按钮导出：\(error.localizedDescription)"
        }
    }

    private func restoreSavedReportURL() {
        guard savedReportURL == nil,
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let urls = try? FileManager.default.contentsOfDirectory(
                at: documents.appendingPathComponent("DanmakuBenchmarks", isDirectory: true),
                includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        savedReportURL = urls.filter { $0.pathExtension == "txt" }.max { lhs, rhs in
            let left = try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            let right = try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            return (left ?? .distantPast) < (right ?? .distantPast)
        }
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
