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

    nonisolated static var current: PlaybackEnvironment {
        PlaybackEnvironment(
            networkClass: NetworkPathSnapshot.shared.currentNetworkClass,
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }

    nonisolated var shouldPreferConservativePlayback: Bool {
        isLowPowerModeEnabled || networkClass == .cellular || networkClass == .constrained
    }

    nonisolated var fastStartQuality: Int {
        shouldPreferConservativePlayback ? 64 : 80
    }

    nonisolated var preferredQualityLadder: [Int] {
        if shouldPreferConservativePlayback {
            return [64, 80, 74, 32, 16, 6]
        }
        return [80, 112, 116, 120, 74, 64, 32, 16, 6]
    }

    nonisolated var preferredForwardBufferDuration: TimeInterval {
        shouldPreferConservativePlayback ? 0.02 : 0.06
    }

    nonisolated var maxBufferDuration: TimeInterval {
        shouldPreferConservativePlayback ? 0.75 : 1.4
    }

    nonisolated var preferredPlayURLStartupGrace: UInt64 {
        switch networkClass {
        case .wifi:
            return 900_000_000
        case .unknown:
            return 700_000_000
        case .cellular, .constrained:
            return 350_000_000
        }
    }
}

final class NetworkPathSnapshot: @unchecked Sendable {
    static let shared = NetworkPathSnapshot()

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

    var currentNetworkClass: PlaybackEnvironment.NetworkClass {
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
