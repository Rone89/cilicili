import Combine
import SwiftUI
import UIKit

/// 横屏顶部状态图标的数据源：只保留真实电量（充电状态）。
@MainActor
final class VideoDetailStatusBatteryMonitor: ObservableObject {
    @Published private(set) var batteryLevel: Double?
    @Published private(set) var isCharging = false

    private var observers: [NSObjectProtocol] = []

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        refresh()
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: UIDevice.batteryLevelDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        )
        observers.append(
            center.addObserver(
                forName: UIDevice.batteryStateDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        )
    }

    deinit {
        let center = NotificationCenter.default
        observers.forEach { center.removeObserver($0) }
    }

    private func refresh() {
        let level = UIDevice.current.batteryLevel
        batteryLevel = level >= 0 ? Double(level) : nil
        let state = UIDevice.current.batteryState
        isCharging = state == .charging || state == .full
    }
}

/// 横屏顶部居中的状态图标：status-trio 画布（120×120）的电池环 + 中间时间。
/// 电池环比例不变；中间不再显示网络信息，底部四点已移除。
struct VideoDetailFullscreenStatusClockIcon: View {
    @StateObject private var battery = VideoDetailStatusBatteryMonitor()
    var size: CGFloat = 68

    private var scale: CGFloat { size / 120 }

    private var batteryTint: Color {
        if battery.isCharging { return Color(red: 0.20, green: 0.78, blue: 0.35) }
        if let level = battery.batteryLevel, level <= 0.2 {
            return Color(red: 1.0, green: 0.23, blue: 0.19)
        }
        return .white
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            Canvas { graphics, _ in
                drawBattery(in: &graphics)
                drawTime(context.date, in: &graphics)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.55), radius: 3, x: 0, y: 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: - 电池环

    private func drawBattery(in context: inout GraphicsContext) {
        let center = CGPoint(x: 59.5 * scale, y: 61.487 * scale)
        let radius = 51.5 * scale
        let style = StrokeStyle(lineWidth: 7.2 * scale, lineCap: .round)

        var track = Path()
        track.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(148.69),
            endAngle: .degrees(148.69 + 242.6198),
            clockwise: false
        )
        context.stroke(track, with: .color(.white.opacity(0.22)), style: style)

        guard let level = battery.batteryLevel, level > 0.005 else { return }
        var fill = Path()
        fill.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(148.69),
            endAngle: .degrees(148.69 + 242.6198 * min(max(level, 0), 1)),
            clockwise: false
        )
        context.stroke(fill, with: .color(batteryTint), style: style)
    }

    // MARK: - 中间时间

    private func drawTime(_ date: Date, in context: inout GraphicsContext) {
        let text = date.formatted(date: .omitted, time: .shortened)
        let resolved = context.resolve(
            Text(text)
                .font(.system(size: 28 * scale, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
        )
        context.draw(resolved, at: CGPoint(x: 59.5 * scale, y: 61.5 * scale), anchor: .center)
    }

    private var accessibilitySummary: String {
        let levelText = battery.batteryLevel.map { "电量 \(Int(($0 * 100).rounded()))%" } ?? "电量未知"
        let timeText = Date().formatted(date: .omitted, time: .shortened)
        return "\(timeText)，\(levelText)"
    }
}
