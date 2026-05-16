import Foundation
import Network

struct PlaybackEnvironment: Sendable {
    enum NetworkClass: Sendable {
        case wifi
        case cellular
        case constrained
        case unknown
    }

    let networkClass: NetworkClass
    let isLowPowerModeEnabled: Bool
    let isThermallyConstrained: Bool

    nonisolated static var current: PlaybackEnvironment {
        let thermalState = ProcessInfo.processInfo.thermalState
        return PlaybackEnvironment(
            networkClass: NetworkPathSnapshot.shared.currentNetworkClass,
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            isThermallyConstrained: thermalState == .serious || thermalState == .critical
        )
    }

    nonisolated var shouldPreferConservativePlayback: Bool {
        let isConstrainedNetwork: Bool
        switch networkClass {
        case .cellular, .constrained:
            isConstrainedNetwork = true
        case .wifi, .unknown:
            isConstrainedNetwork = false
        }
        return isLowPowerModeEnabled
            || isThermallyConstrained
            || isConstrainedNetwork
    }

    nonisolated var fastStartQuality: Int {
        64
    }

    nonisolated var startupPreferredQualityCeiling: Int {
        64
    }

    nonisolated var preferredQualityLadder: [Int] {
        if shouldPreferConservativePlayback {
            return [64, 80, 74, 32, 16, 6]
        }
        return [80, 112, 116, 120, 74, 64, 32, 16, 6]
    }

    nonisolated var preferredForwardBufferDuration: TimeInterval {
        shouldPreferConservativePlayback ? 0.08 : 0.16
    }

    nonisolated var maxBufferDuration: TimeInterval {
        shouldPreferConservativePlayback ? 1.2 : 2.0
    }

    nonisolated var preferredPlayURLStartupGrace: UInt64 {
        switch networkClass {
        case .wifi:
            return 160_000_000
        case .unknown:
            return 140_000_000
        case .cellular, .constrained:
            return 90_000_000
        }
    }

    nonisolated var startupWarmupPrepareBudget: TimeInterval {
        switch networkClass {
        case .wifi:
            return 0.14
        case .unknown:
            return 0.11
        case .cellular, .constrained:
            return 0.08
        }
    }
}

final class NetworkPathSnapshot: @unchecked Sendable {
    nonisolated static let shared = NetworkPathSnapshot()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "cc.bili.network-path")
    private let lock = NSLock()
    private var cachedClass: PlaybackEnvironment.NetworkClass = .unknown

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.update(path)
        }
        monitor.start(queue: queue)
    }

    nonisolated var currentNetworkClass: PlaybackEnvironment.NetworkClass {
        lock.withLock { cachedClass }
    }

    private func update(_ path: NWPath) {
        let value: PlaybackEnvironment.NetworkClass
        if path.isConstrained {
            value = .constrained
        } else if path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) {
            value = .wifi
        } else if path.usesInterfaceType(.cellular) {
            value = .cellular
        } else {
            value = .unknown
        }
        lock.withLock {
            cachedClass = value
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
