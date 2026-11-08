import Combine
import CoreTelephony
import Network
import os
import SwiftUI
import UIKit

/// 私有信号探针：iOS 无公开 API 获取 Wi-Fi RSSI 与蜂窝信号格数，
/// 这里用 dlsym 读取 CoreTelephony / MobileWiFi 的私有符号。
/// 任何一步失败都返回 nil，由调用方回退到公开信息（连接态 / 制式）。
/// 仅用于自签名侧载构建；上架 App Store 属违规用法。
final class VideoDetailPrivateSignalProbe {
    static let shared = VideoDetailPrivateSignalProbe()

    /// 私有探针默认关闭（Build 131 在横屏全屏时闪退，先回退到公开信息）。
    /// 需要实测时用启动参数 `--enable-private-signal-probe` 打开。
    private var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--enable-private-signal-probe")
    }

    private let logger = Logger(subsystem: "cc.bili", category: "SignalProbe")

    private var ctConnection: UnsafeMutableRawPointer?
    private var ctStrengthFunction: (@convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<Int32>?) -> Int32)?
    private var ctResolved = false

    private var wifiDevice: UnsafeMutableRawPointer?
    private var wifiCopyNetwork: (@convention(c) (UnsafeMutableRawPointer?) -> Unmanaged<AnyObject>?)?
    private var wifiNetworkProperty: (@convention(c) (AnyObject?, CFString) -> Unmanaged<AnyObject>?)?
    private var wifiResolved = false

    private init() {}

    // MARK: - 蜂窝

    /// 返回 0...4 的信号格数；拿不到返回 nil。
    func cellularBars() -> Int? {
        guard isEnabled else { return nil }
        resolveCellularIfNeeded()
        guard let connection = ctConnection, let strength = ctStrengthFunction else { return nil }
        var raw: Int32 = 0
        _ = strength(connection, &raw)
        let value = Int(raw)
        guard raw != 0 || value == 0 else { return nil }
        let bars: Int
        if (0...5).contains(value) {
            bars = value
        } else if value < 0 {
            // 部分系统返回 dBm。
            switch value {
            case ...(-90): bars = 0
            case ...(-80): bars = 1
            case ...(-70): bars = 2
            case ...(-60): bars = 3
            default: bars = 4
            }
        } else {
            bars = 0
        }
        return min(4, max(0, bars))
    }

    private func resolveCellularIfNeeded() {
        guard !ctResolved else { return }
        ctResolved = true
        guard let handle = dlopen("/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony", RTLD_LAZY) else {
            logger.debug("CoreTelephony dlopen failed")
            return
        }
        typealias CreateFn = @convention(c) (CFAllocator?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
        typealias StrengthFn = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<Int32>?) -> Int32
        guard let createSymbol = dlsym(handle, "CTServerConnectionCreate"),
              let strengthSymbol = dlsym(handle, "_CTServerConnectionGetSignalStrength")
                ?? dlsym(handle, "CTServerConnectionGetSignalStrength")
        else {
            logger.debug("CT signal symbols missing")
            return
        }
        let create = unsafeBitCast(createSymbol, to: CreateFn.self)
        ctStrengthFunction = unsafeBitCast(strengthSymbol, to: StrengthFn.self)
        ctConnection = create(kCFAllocatorDefault, nil, nil)
        logger.debug("CT signal probe ready: \(self.ctConnection != nil)")
    }

    // MARK: - Wi-Fi

    /// 返回 RSSI（dBm，通常 -30...-90）；拿不到返回 nil。
    func wifiRSSI() -> Int? {
        guard isEnabled else { return nil }
        resolveWiFiIfNeeded()
        guard let device = wifiDevice,
              let copyNetwork = wifiCopyNetwork,
              let readProperty = wifiNetworkProperty,
              let network = copyNetwork(device)?.takeRetainedValue()
        else { return nil }
        guard let value = readProperty(network, "RSSI" as CFString)?.takeRetainedValue() as? NSNumber else {
            return nil
        }
        return value.intValue
    }

    private func resolveWiFiIfNeeded() {
        guard !wifiResolved else { return }
        wifiResolved = true
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MobileWiFi.framework/MobileWiFi", RTLD_LAZY) else {
            logger.debug("MobileWiFi dlopen failed")
            return
        }
        typealias ManagerCreateFn = @convention(c) (CFAllocator?, UInt32) -> UnsafeMutableRawPointer?
        typealias GetDeviceFn = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> UnsafeMutableRawPointer?
        typealias CopyNetworkFn = @convention(c) (UnsafeMutableRawPointer?) -> Unmanaged<AnyObject>?
        typealias GetPropertyFn = @convention(c) (AnyObject?, CFString) -> Unmanaged<AnyObject>?

        guard let managerSymbol = dlsym(handle, "WiFiManagerClientCreate"),
              let deviceSymbol = dlsym(handle, "WiFiManagerClientGetDevice"),
              let copySymbol = dlsym(handle, "WiFiDeviceClientCopyCurrentNetwork"),
              let propertySymbol = dlsym(handle, "WiFiNetworkGetProperty")
        else {
            logger.debug("MobileWiFi symbols missing")
            return
        }
        let createManager = unsafeBitCast(managerSymbol, to: ManagerCreateFn.self)
        let getDevice = unsafeBitCast(deviceSymbol, to: GetDeviceFn.self)
        wifiCopyNetwork = unsafeBitCast(copySymbol, to: CopyNetworkFn.self)
        wifiNetworkProperty = unsafeBitCast(propertySymbol, to: GetPropertyFn.self)
        guard let manager = createManager(kCFAllocatorDefault, 0) else {
            logger.debug("WiFiManagerClientCreate returned nil")
            return
        }
        for name in ["en0", "en1", "awdl0"] {
            if let device = name.withCString({ getDevice(manager, $0) }) {
                wifiDevice = device
                break
            }
        }
        logger.debug("MobileWiFi probe ready: \(self.wifiDevice != nil)")
    }
}

/// 横屏状态组合图标的数据源。
@MainActor
final class VideoDetailStatusTrioMonitor: ObservableObject {
    @Published private(set) var batteryLevel: Double?
    @Published private(set) var isCharging = false
    @Published private(set) var wifiState: WiFiState = .unavailable
    @Published private(set) var wifiRSSI: Int?
    @Published private(set) var cellularBars: Int = 0
    @Published private(set) var cellularTechnology: String?

    enum WiFiState {
        case unavailable
        case connected
        case connectedWithoutInternet
    }

    private let pathMonitor = NWPathMonitor()
    private let pathQueue = DispatchQueue(label: "cc.bili.statusTrio.path")
    private let telephony = CTTelephonyNetworkInfo()
    private let probe = VideoDetailPrivateSignalProbe.shared
    private var batteryObservers: [NSObjectProtocol] = []
    private var refreshTimer: Timer?

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        refreshBattery()
        refreshNetworkDetails()

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

        // 信号强度/制式没有通知，低频轮询兜底。
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshNetworkDetails() }
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
            wifiRSSI = nil
            return
        }
        if path.usesInterfaceType(.wifi) {
            wifiState = .connected
            wifiRSSI = probe.wifiRSSI()
        } else {
            wifiState = .unavailable
            wifiRSSI = nil
        }
    }

    private func refreshNetworkDetails() {
        wifiRSSI = wifiState == .connected ? probe.wifiRSSI() : nil
        cellularTechnology = currentCellularTechnology()
        cellularBars = probe.cellularBars() ?? fallbackBars(for: cellularTechnology)
    }

    private func currentCellularTechnology() -> String? {
        let technologies = Array(telephony.serviceCurrentRadioAccessTechnology?.values ?? [:].values)
        if technologies.contains(where: { $0 == CTRadioAccessTechnologyNR || $0 == CTRadioAccessTechnologyNRNSA }) {
            return "5G"
        }
        if technologies.contains(CTRadioAccessTechnologyLTE) {
            return "4G"
        }
        if technologies.contains(where: {
            $0 == CTRadioAccessTechnologyWCDMA || $0 == CTRadioAccessTechnologyHSDPA || $0 == CTRadioAccessTechnologyHSUPA
        }) {
            return "3G"
        }
        if technologies.contains(where: {
            $0 == CTRadioAccessTechnologyGPRS || $0 == CTRadioAccessTechnologyEdge
        }) {
            return "2G"
        }
        return nil
    }

    /// 私有 API 不可用时的兜底：按制式给档位。
    private func fallbackBars(for technology: String?) -> Int {
        switch technology {
        case "5G": return 4
        case "4G": return 3
        case "3G": return 2
        case "2G": return 1
        default: return 0
        }
    }
}

/// status-trio 风格的三段式图标（120×120 画布）：
/// 电池圆环 + 中间 Wi-Fi / 蜂窝制式 + 底部四点信号格。
struct VideoDetailFullscreenStatusTrioIcon: View {
    @StateObject private var monitor = VideoDetailStatusTrioMonitor()
    var size: CGFloat = 46

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
            drawMiddle(in: &context)
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
        let style = StrokeStyle(lineWidth: 8 * scale, lineCap: .round)

        var track = Path()
        track.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(148.69),
            endAngle: .degrees(148.69 + 242.6198),
            clockwise: false
        )
        context.stroke(track, with: .color(.white.opacity(0.22)), style: style)

        guard let level = monitor.batteryLevel, level > 0.005 else { return }
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

    // MARK: - 中间：Wi-Fi 或蜂窝制式

    private func drawMiddle(in context: inout GraphicsContext) {
        if monitor.wifiState != .unavailable {
            drawWiFi(in: &context)
        } else if let technology = monitor.cellularTechnology {
            drawCellularText(technology, in: &context)
        } else {
            drawWiFi(in: &context, forcedDim: true)
        }
    }

    private func drawWiFi(in context: inout GraphicsContext, forcedDim: Bool = false) {
        let style = StrokeStyle(lineWidth: 7 * scale, lineCap: .round)
        let color: Color = {
            if forcedDim { return .white.opacity(0.22) }
            if monitor.wifiState == .connectedWithoutInternet { return .white.opacity(0.45) }
            return .white
        }()

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

        guard !forcedDim, monitor.wifiState != .unavailable else { return }

        // 用 RSSI 分档决定画几条弧（拿不到 RSSI 时按已连接画满）。
        let arcs: Int = {
            guard let rssi = monitor.wifiRSSI else { return 3 }
            switch rssi {
            case ...(-75): return 1
            case ...(-62): return 2
            default: return 3
            }
        }()

        if arcs >= 2 {
            var middle = Path()
            middle.addArc(
                center: CGPoint(x: 59.5 * scale, y: 78.89 * scale),
                radius: 18.5 * scale,
                startAngle: .degrees(227.5),
                endAngle: .degrees(312.5),
                clockwise: false
            )
            context.stroke(middle, with: .color(color), style: style)
        }
        if arcs >= 3 {
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
    }

    private func drawCellularText(_ text: String, in context: inout GraphicsContext) {
        let font = Font.system(size: 26 * scale, weight: .bold, design: .rounded)
        let resolved = context.resolve(
            Text(text)
                .font(font)
                .foregroundStyle(.white)
                .monospacedDigit()
        )
        context.draw(resolved, at: CGPoint(x: 59.5 * scale, y: 70 * scale), anchor: .center)
    }

    // MARK: - 底部四点（蜂窝信号格）

    private func drawLevelDots(in context: inout GraphicsContext) {
        let points: [CGPoint] = [
            CGPoint(x: 33, y: 104.2),
            CGPoint(x: 50.5, y: 111.2),
            CGPoint(x: 68.5, y: 111.7),
            CGPoint(x: 86, y: 105.8),
        ]
        let radius = 5.5 * scale
        for (index, point) in points.enumerated() {
            let isOn = index < monitor.cellularBars
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
        let networkText: String = {
            if monitor.wifiState != .unavailable {
                let rssi = monitor.wifiRSSI.map { "，信号 \($0) dBm" } ?? ""
                return "Wi-Fi 已连接\(rssi)"
            }
            if let technology = monitor.cellularTechnology {
                return "蜂窝 \(technology)，信号 \(monitor.cellularBars) 格"
            }
            return "无网络"
        }()
        return "\(batteryText)，\(networkText)"
    }
}
