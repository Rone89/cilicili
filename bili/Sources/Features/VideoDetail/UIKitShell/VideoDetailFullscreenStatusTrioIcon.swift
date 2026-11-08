import Combine
import SwiftUI
import UIKit

/// 横屏顶部状态栏的数据源：只保留真实电量与充电状态。
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

struct VideoDetailFullscreenClockStatus: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            let formattedTime = context.date.formatted(date: .omitted, time: .shortened)
            Text(formattedTime)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .accessibilityLabel("时间，\(formattedTime)")
                .accessibilityIdentifier("video.fullscreen.status.time")
        }
    }
}

struct VideoDetailFullscreenBatteryStatus: View {
    @StateObject private var battery = VideoDetailStatusBatteryMonitor()

    private var batteryTint: Color {
        if battery.isCharging { return Color(red: 0.20, green: 0.78, blue: 0.35) }
        if let level = battery.batteryLevel, level <= 0.2 {
            return Color(red: 1.0, green: 0.23, blue: 0.19)
        }
        return .white
    }

    private var batterySymbol: String {
        guard let level = battery.batteryLevel else { return "battery.0percent" }
        return switch level {
        case ...0.125: "battery.0percent"
        case ...0.375: "battery.25percent"
        case ...0.625: "battery.50percent"
        case ...0.875: "battery.75percent"
        default: "battery.100percent"
        }
    }

    private var percentageText: String {
        battery.batteryLevel.map { "\(Int(($0 * 100).rounded()))%" } ?? "--%"
    }

    private var accessibilitySummary: String {
        let levelText = battery.batteryLevel.map {
            "电量 \(Int(($0 * 100).rounded()))%"
        } ?? "电量未知"
        return battery.isCharging ? "\(levelText)，正在充电" : levelText
    }

    var body: some View {
        HStack(spacing: 7) {
            Text(percentageText)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(batteryTint)

            Image(systemName: batterySymbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(batteryTint)
                .overlay(alignment: .bottomTrailing) {
                    if battery.isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(batteryTint)
                            .offset(x: 3, y: 3)
                    }
                }
        }
        .padding(.horizontal, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityIdentifier("video.fullscreen.status.battery")
    }
}
