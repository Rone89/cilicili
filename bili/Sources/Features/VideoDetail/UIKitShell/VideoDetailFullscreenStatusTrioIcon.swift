import Combine
import CoreTelephony
import Network
import SwiftUI
import UIKit

/// 横屏状态组合图标的数据源。
///
/// 公开 API 能拿到的真实信息：
/// - 电量 / 充电状态：`UIDevice`
/// - Wi-Fi 是否承载流量、是否有互联网：`NWPathMonitor`
/// - 蜂窝制式（5G/LTE/3G/2G）：`CTTelephonyNetworkInfo`
///
/// 拿不到（iOS 无公开 API）：Wi-Fi 信号强度、蜂窝信号格数。
/// 因此 Wi-Fi 用「连接/无互联网」两态，底部 4 点用制式档位而不是信号强度。
@MainActor
final class VideoDetailStatusTrioMonitor: ObservableObject {
    @Published private(set) var batteryLevel: Double?
    @Published private(set) var isCharging = false
    @Published private(set) var wifiState: WiFiState = .unavailable
    @Published private(set) var cellularLevel: Int = 0

    enum WiFiState {
        case unavailable
        case connected
        case connectedWithoutInternet
    }

    private let pathMonitor = NWPathMonitor()
    private let pathQueue = DispatchQueue(label: "cc.bili.statusTrio.path")
    private let telephony = CTTelephonyNetworkInfo()
    private var batteryObservers: [NSObjectProtocol] = []
    private var refreshTimer: Timer?

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        refreshBattery()
        refreshCellularLevel()

        let center = NotificationCenter.default
        batteryObservers.append(
            center.addObserver(
                forName: UIDevice.batteryLevelDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.refreshBattery() }
            }
        )
        batteryObservers.append(
            center.addObserver(
                forName: UIDevice.batteryStateDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.refreshBattery() }
            }
        )

        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.apply(path: path)
            }
        }
        pathMonitor.start(queue: pathQueue)

        // 制式切换（5G/4G）没有通知，低频轮询兜底。
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshCellularLevel() }
        }
    }

    deinit {
        pathMonitor.cancel()
        refreshTimer?.invalidate()
        let center = NotificationCenter.default
        batteryObservers.forEach { center.removeObserver($0) }
    }

    private func refreshBattery() {
        let level = UIDevice.current.batteryLevel
        batteryLevel = level >= 0 ? Double(level) : nil
        let state = UIDevice.current.batteryState
        isCharging = state == .charging || state == .full
    }

    private func apply(path: NWPath) {
        guard path.status == .satisfied else {
            wifiState = .unavailable
            return
        }
        if path.usesInterfaceType(.wifi) {
            wifiState = .connected
        } else if path.usesInterfaceType(.cellular) {
            wifiState = .unavailable
        } else {
            wifiState = .unavailable
        }
    }

    private func refreshCellularLevel() {
        // 5G / NR NSA -> 4，LTE -> 3，3G -> 2，2G -> 1，无服务 -> 0。
        let technologies = Array(telephony.serviceCurrentRadioAccessTechnology?.values ?? [:].values)
        let level: Int
        if technologies.contains(where: { $0 == CTRadioAccessTechnologyNR || $0 == CTRadioAccessTechnologyNRNSA }) {
            level = 4
        } else if technologies.contains(CTRadioAccessTechnologyLTE) {
            level = 3
        } else if technologies.contains(where: {
            $0 == CTRadioAccessTechnologyWCDMA || $0 == CTRadioAccessTechnologyHSDPA || $0 == CTRadioAccessTechnologyHSUPA
        }) {
            level = 2
        } else if technologies.contains(where: {
            $0 == CTRadioAccessTechnologyGPRS || $0 == CTRadioAccessTechnologyEdge
        }) {
            level = 1
        } else {
            level = 0
        }
        cellularLevel = level
    }
}

/// 参照 status-trio 的三段式图标（120×120 画布）：
/// 电池圆环（开口朝下，填充真实电量）+ Wi-Fi 弧 + 底部四点（蜂窝制式档位）。
struct VideoDetailFullscreenStatusTrioIcon: View {
    @StateObject private var monitor = VideoDetailStatusTrioMonitor()
    var size: CGFloat = 32

    private var scale: CGFloat { size / 120 }
    private var batteryTint: Color {
        if monitor.isCharging { return Color(red: 0.20, green: 0.78, blue: 0.35) }
        if let level = monitor.batteryLevel, level <= 0.2 {
            return Color(red: 1.0, green: 0.23, blue: 0.19)
        }
        return .white
    }

    var body: some View {
        Canvas { context, _ in
            drawBattery(in: &context)
            drawWiFi(in: &context)
            drawLevelDots(in: &context)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: - 电池圆环

    private func drawBattery(in context: inout GraphicsContext) {
        let center = CGPoint(x: 59.5 * scale, y: 61.487 * scale)
        let radius = 51.5 * scale
        let startDegrees = 148.69
        let sweepDegrees = 242.6198
        let style = StrokeStyle(lineWidth: 8 * scale, lineCap: .round)

        var track = Path()
        track.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(startDegrees),
            endAngle: .degrees(startDegrees + sweepDegrees),
            clockwise: false
        )
        context.stroke(track, with: .color(.white.opacity(0.22)), style: style)

        guard let level = monitor.batteryLevel, level > 0.005 else { return }
        var fill = Path()
        fill.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(startDegrees),
            endAngle: .degrees(startDegrees + sweepDegrees * min(max(level, 0), 1)),
            clockwise: false
        )
        context.stroke(fill, with: .color(batteryTint), style: style)
    }

    // MARK: - Wi-Fi

    private func drawWiFi(in context: inout GraphicsContext) {
        let style = StrokeStyle(lineWidth: 7 * scale, lineCap: .round)
        let color: Color = {
            switch monitor.wifiState {
            case .connected: return .white
            case .connectedWithoutInternet: return .white.opacity(0.45)
            case .unavailable: return .white.opacity(0.22)
            }
        }()

        // 中心点始终绘制，弧数量表示状态。
        let dotRadius = 4.6 * scale
        let dotCenter = CGPoint(x: 59.5 * scale, y: 76.4 * scale)
        context.fill(
            Path(ellipseIn: CGRect(
                x: dotCenter.x - dotRadius,
                y: dotCenter.y - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            )),
            with: .color(color)
        )

        guard monitor.wifiState != .unavailable else { return }

        var middle = Path()
        middle.addArc(
            center: CGPoint(x: 59.5 * scale, y: 78.89 * scale),
            radius: 18.5 * scale,
            startAngle: .degrees(227.5),
            endAngle: .degrees(312.5),
            clockwise: false
        )
        context.stroke(middle, with: .color(color), style: style)

        guard monitor.wifiState == .connected else { return }

        var outer = Path()
        outer.addArc(
            center: CGPoint(x: 59.5 * scale, y: 78.3 * scale),
            radius: 31 * scale,
            startAngle: .degrees(227.35),
            endAngle: .degrees(312.65),
            clockwise: false
        )
        context.stroke(outer, with: .color(color), style: style)
    }

    // MARK: - 底部四点（蜂窝制式档位）

    private func drawLevelDots(in context: inout GraphicsContext) {
        let points: [CGPoint] = [
            CGPoint(x: 33, y: 104.2),
            CGPoint(x: 50.5, y: 111.2),
            CGPoint(x: 68.5, y: 111.7),
            CGPoint(x: 86, y: 105.8),
        ]
        let radius = 5.5 * scale
        for (index, point) in points.enumerated() {
            let isOn = index < monitor.cellularLevel
            let color: Color = isOn ? .white : .white.opacity(0.22)
            let rect = CGRect(
                x: point.x * scale - radius,
                y: point.y * scale - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.fill(Path(ellipseIn: rect), with: .color(color))
        }
    }

    private var accessibilitySummary: String {
        let batteryText = monitor.batteryLevel.map { "电量 \(Int(($0 * 100).rounded()))%" } ?? "电量未知"
        let wifiText: String = {
            switch monitor.wifiState {
            case .connected: return "Wi-Fi 已连接"
            case .connectedWithoutInternet: return "Wi-Fi 无互联网"
            case .unavailable: return "未连接 Wi-Fi"
            }
        }()
        let cellularText = monitor.cellularLevel > 0 ? "蜂窝制式 \(monitor.cellularLevel) 档" : "无蜂窝网络"
        return "\(batteryText)，\(wifiText)，\(cellularText)"
    }
}
