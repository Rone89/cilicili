#if DEBUG
import SwiftUI
import UIKit

/// Local, copyright-free text fixture. The density override is DEBUG-only and
/// does not bypass any normal player's admission policy.
struct DanmakuRendererBenchmarkView: View {
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
            Picker("活跃弹幕", selection: $density) {
                ForEach([10, 50, 100, 300, 600], id: \.self) { Text("\($0)").tag($0) }
            }.pickerStyle(.segmented)
                .accessibilityIdentifier("danmaku.benchmark.density")
            BenchmarkOverlay(metal: metal, density: density, revision: revision,
                time: time, playing: playing, rate: rate, settings: settings)
                .background(Color(white: 0.14))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
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
            Text("\(time, specifier: "%.2f")s · 固定文字 / 相同输入 · 显示区域允许重叠，仅用于压力测试。")
                .font(.caption)
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
        .onChange(of: density) { _, _ in time = 1; revision &+= 1 }
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

    func makeUIView(context: Context) -> DanmakuRendererHostView { DanmakuRendererHostView(frame: .zero) }
    func updateUIView(_ view: DanmakuRendererHostView, context: Context) {
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
