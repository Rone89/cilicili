import Foundation
import Darwin

struct PlaybackCDNProbeResult: Identifiable, Codable, Equatable, Sendable {
    let preference: PlaybackCDNPreference
    let elapsedMilliseconds: Int?
    let didSucceed: Bool
    let errorDescription: String?
    let addressFamily: PlaybackNetworkAddressFamily?

    private enum CodingKeys: String, CodingKey {
        case preference
        case elapsedMilliseconds
        case didSucceed
        case errorDescription
        case addressFamily
    }

    init(
        preference: PlaybackCDNPreference,
        elapsedMilliseconds: Int?,
        didSucceed: Bool,
        errorDescription: String?,
        addressFamily: PlaybackNetworkAddressFamily? = nil
    ) {
        self.preference = preference
        self.elapsedMilliseconds = elapsedMilliseconds
        self.didSucceed = didSucceed
        self.errorDescription = errorDescription
        self.addressFamily = addressFamily
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.preference = try container.decode(PlaybackCDNPreference.self, forKey: .preference)
        self.elapsedMilliseconds = try container.decodeIfPresent(Int.self, forKey: .elapsedMilliseconds)
        self.didSucceed = try container.decode(Bool.self, forKey: .didSucceed)
        self.errorDescription = try container.decodeIfPresent(String.self, forKey: .errorDescription)
        self.addressFamily = try container.decodeIfPresent(PlaybackNetworkAddressFamily.self, forKey: .addressFamily)
    }

    var id: PlaybackCDNPreference { preference }

    var failureReason: String? {
        guard !didSucceed else { return nil }
        return errorDescription?.isEmpty == false ? errorDescription : "连接失败"
    }
}

struct PlaybackCDNProbeSnapshot: Codable, Equatable, Sendable {
    static let defaultFreshnessInterval: TimeInterval = 24 * 60 * 60

    let probedAt: Date
    let recommendedPreference: PlaybackCDNPreference?
    let results: [PlaybackCDNProbeResult]

    var successfulResults: [PlaybackCDNProbeResult] {
        results.filter { $0.didSucceed && $0.elapsedMilliseconds != nil }
    }

    func result(for preference: PlaybackCDNPreference) -> PlaybackCDNProbeResult? {
        results.first { $0.preference == preference }
    }

    func isExpired(now: Date = Date(), freshnessInterval: TimeInterval = Self.defaultFreshnessInterval) -> Bool {
        now.timeIntervalSince(probedAt) >= freshnessInterval
    }
}

@MainActor
final class PlaybackCDNProbeCoordinator {
    static let shared = PlaybackCDNProbeCoordinator()

    private var refreshTask: Task<PlaybackCDNProbeSnapshot?, Never>?
    private var refreshToken: UUID?
    private var lastAdaptiveRefreshAt: Date?
    private var lastPressureRefreshAt: Date?
    private let pressureRefreshInterval: TimeInterval = 10 * 60
    private let failedProbeRetryInterval: TimeInterval = 15 * 60

    private init() {}

    func refreshIfNeeded(libraryStore: LibraryStore) {
        guard refreshTask == nil else { return }
        guard shouldRefresh(libraryStore: libraryStore) else { return }
        PlayerMetricsLog.signpostEvent(
            "PlaybackCDNRefresh",
            message: "trigger=adaptive preference=\(libraryStore.playbackCDNPreference.rawValue)"
        )
        startRefresh(libraryStore: libraryStore)
    }

    func refreshOnAppActivationIfNeeded(libraryStore: LibraryStore) {
        guard libraryStore.playbackCDNProbeRefreshPolicy == .appLaunch else {
            refreshIfNeeded(libraryStore: libraryStore)
            return
        }
        refreshNow(libraryStore: libraryStore, trigger: "appActivation")
    }

    func refreshNow(libraryStore: LibraryStore, trigger: String = "manual") {
        guard refreshTask == nil else { return }
        guard libraryStore.playbackCDNPreference == .automatic else { return }
        PlayerMetricsLog.signpostEvent(
            "PlaybackCDNRefresh",
            message: "trigger=\(trigger) preference=\(libraryStore.playbackCDNPreference.rawValue)"
        )
        startRefresh(libraryStore: libraryStore)
    }

    func refreshForPlaybackPressure(libraryStore: LibraryStore) {
        guard refreshTask == nil else { return }
        guard libraryStore.playbackCDNPreference == .automatic else { return }
        let now = Date()
        if let lastPressureRefreshAt,
           now.timeIntervalSince(lastPressureRefreshAt) < pressureRefreshInterval {
            return
        }
        lastPressureRefreshAt = now
        PlayerMetricsLog.signpostEvent(
            "PlaybackCDNRefresh",
            message: "trigger=pressure preference=\(libraryStore.playbackCDNPreference.rawValue)"
        )
        startRefresh(libraryStore: libraryStore)
    }

    func prepareRecommendationForImmediatePlaybackIfNeeded(
        libraryStore: LibraryStore,
        timeout: TimeInterval = 0.75
    ) async {
        let signpostState = PlayerMetricsLog.beginSignpostedInterval(
            "PlaybackCDNImmediate",
            message: "timeout=\(String(format: "%.2f", timeout))"
        )
        var signpostMessage = "waiting"
        defer {
            PlayerMetricsLog.endSignpostedInterval(
                "PlaybackCDNImmediate",
                signpostState,
                message: signpostMessage
            )
        }
        guard libraryStore.playbackCDNPreference == .automatic else {
            signpostMessage = "skipped preference=\(libraryStore.playbackCDNPreference.rawValue)"
            return
        }
        guard libraryStore.automaticPlaybackCDNRecommendation == nil else {
            signpostMessage = "ready existing=\(libraryStore.automaticPlaybackCDNRecommendation?.rawValue ?? "-")"
            return
        }
        refreshIfNeeded(libraryStore: libraryStore)

        let deadline = Date().addingTimeInterval(max(0, timeout))
        let initialWait = min(max(timeout * 0.28, 0.08), 0.22)
        if await waitForAutomaticRecommendation(
            libraryStore: libraryStore,
            until: Date().addingTimeInterval(initialWait)
        ) {
            signpostMessage = "ready waited"
            return
        }

        guard libraryStore.automaticPlaybackCDNRecommendation == nil,
              !Task.isCancelled
        else {
            signpostMessage = "ready after wait"
            return
        }

        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0.12 else {
            signpostMessage = "timeout budget exhausted"
            return
        }

        let addressFamilyPreference = libraryStore.playbackNetworkAddressFamilyPreference
        let quickSnapshot = await PlaybackCDNProbeService.quickRecommendedSnapshot(
            addressFamilyPreference: addressFamilyPreference,
            timeout: remaining
        )

        guard !Task.isCancelled,
              libraryStore.playbackCDNPreference == .automatic,
              libraryStore.automaticPlaybackCDNRecommendation == nil,
              quickSnapshot.recommendedPreference != nil
        else {
            signpostMessage = "quick no recommendation"
            return
        }
        libraryStore.setPlaybackCDNProbeSnapshot(quickSnapshot)
        signpostMessage = "quick \(quickSnapshot.recommendedPreference?.rawValue ?? "-")"
    }

    private func waitForAutomaticRecommendation(
        libraryStore: LibraryStore,
        until deadline: Date
    ) async -> Bool {
        while libraryStore.automaticPlaybackCDNRecommendation == nil,
              Date() < deadline,
              !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 60_000_000)
        }
        return libraryStore.automaticPlaybackCDNRecommendation != nil
    }

    private func shouldRefresh(libraryStore: LibraryStore) -> Bool {
        guard libraryStore.playbackCDNPreference == .automatic else { return false }
        guard let snapshot = libraryStore.playbackCDNProbeSnapshotForCurrentContext else { return true }
        if snapshot.isExpired(freshnessInterval: libraryStore.playbackCDNProbeRefreshInterval) {
            return true
        }
        if snapshot.recommendedPreference == nil,
           snapshot.isExpired(freshnessInterval: failedProbeRetryInterval) {
            return true
        }
        guard PlayerPerformanceStore.shared.shouldRefreshPlaybackCDNProbe(
            isEnabled: libraryStore.isPlaybackAutoOptimizationEnabled
        ) else {
            return false
        }
        if snapshot.isExpired(freshnessInterval: libraryStore.playbackCDNProbeRefreshInterval) {
            return true
        }
        guard let lastAdaptiveRefreshAt else {
            return true
        }
        return Date().timeIntervalSince(lastAdaptiveRefreshAt) >= libraryStore.playbackCDNProbeRefreshInterval
    }

    private func startRefresh(libraryStore: LibraryStore) {
        let token = UUID()
        refreshToken = token
        refreshTask = Task(priority: .utility) { [weak self, weak libraryStore] in
            guard let libraryStore else { return nil }
            let signpostState = PlayerMetricsLog.beginSignpostedInterval(
                "PlaybackCDNRefresh",
                message: "mode=full preference=\(libraryStore.playbackCDNPreference.rawValue)"
            )
            var signpostMessage = "mode=full loading"
            defer {
                PlayerMetricsLog.endSignpostedInterval(
                    "PlaybackCDNRefresh",
                    signpostState,
                    message: signpostMessage
                )
            }
            let addressFamilyPreference = await MainActor.run {
                libraryStore.playbackNetworkAddressFamilyPreference
            }
            let snapshot = await PlaybackCDNProbeService.recommendedSnapshot(
                addressFamilyPreference: addressFamilyPreference
            )
            await MainActor.run {
                guard let self, self.refreshToken == token, !Task.isCancelled else { return }
                libraryStore.setPlaybackCDNProbeSnapshot(snapshot)
                if !libraryStore.needsPlaybackCDNProbeRefresh {
                    self.lastAdaptiveRefreshAt = Date()
                }
                self.refreshTask = nil
                self.refreshToken = nil
            }
            signpostMessage = "mode=full result=\(snapshot.recommendedPreference?.rawValue ?? "-")"
            return snapshot
        }
    }
}

enum PlaybackCDNProbeService {
    private static let probePath = "/upgcxcode/00/00/1/1.m4s"
    private static let timeout: TimeInterval = 2.2

    static func probeAll(
        addressFamilyPreference: PlaybackNetworkAddressFamilyPreference = .automatic
    ) async -> [PlaybackCDNProbeResult] {
        let candidates = PlaybackCDNPreference.manualProbeCandidates
        return await withTaskGroup(of: PlaybackCDNProbeResult.self) { group in
            for candidate in candidates {
                group.addTask(priority: .utility) {
                    await probe(
                        candidate,
                        addressFamilyPreference: addressFamilyPreference
                    )
                }
            }

            var results = [PlaybackCDNProbeResult]()
            for await result in group {
                results.append(result)
            }
            return sortedResults(results)
        }
    }

    static func quickRecommendedSnapshot(
        addressFamilyPreference: PlaybackNetworkAddressFamilyPreference = .automatic,
        timeout: TimeInterval = 0.55
    ) async -> PlaybackCDNProbeSnapshot {
        let results = await quickProbeResults(
            addressFamilyPreference: addressFamilyPreference,
            timeout: timeout
        )
        let recommendation = results.first {
            $0.didSucceed && $0.elapsedMilliseconds != nil
        }?.preference
        return PlaybackCDNProbeSnapshot(
            probedAt: Date(),
            recommendedPreference: recommendation,
            results: results
        )
    }

    static func recommendedPreference(
        addressFamilyPreference: PlaybackNetworkAddressFamilyPreference = .automatic
    ) async -> (preference: PlaybackCDNPreference?, results: [PlaybackCDNProbeResult]) {
        let results = await probeAll(addressFamilyPreference: addressFamilyPreference)
        let recommendation = results.first {
            $0.didSucceed && $0.elapsedMilliseconds != nil
        }?.preference
        return (recommendation, results)
    }

    static func recommendedSnapshot(
        addressFamilyPreference: PlaybackNetworkAddressFamilyPreference = .automatic
    ) async -> PlaybackCDNProbeSnapshot {
        let recommendation = await recommendedPreference(
            addressFamilyPreference: addressFamilyPreference
        )
        return PlaybackCDNProbeSnapshot(
            probedAt: Date(),
            recommendedPreference: recommendation.preference,
            results: recommendation.results
        )
    }

    private static func probe(
        _ preference: PlaybackCDNPreference,
        addressFamilyPreference: PlaybackNetworkAddressFamilyPreference,
        timeout: TimeInterval = 2.2
    ) async -> PlaybackCDNProbeResult {
        guard let host = preference.host,
              let url = URL(string: "https://\(host)\(probePath)")
        else {
            return PlaybackCDNProbeResult(
                preference: preference,
                elapsedMilliseconds: nil,
                didSucceed: false,
                errorDescription: "没有可测速 Host"
            )
        }

        if let requiredFamily = addressFamilyPreference.requiredFamily {
            do {
                let resolvedFamilies = try resolvedAddressFamilies(for: host)
                guard resolvedFamilies.contains(requiredFamily) else {
                    return PlaybackCDNProbeResult(
                        preference: preference,
                        elapsedMilliseconds: nil,
                        didSucceed: false,
                        errorDescription: "未解析到 \(requiredFamily.title) 地址",
                        addressFamily: nil
                    )
                }
            } catch {
                return PlaybackCDNProbeResult(
                    preference: preference,
                    elapsedMilliseconds: nil,
                    didSucceed: false,
                    errorDescription: dnsFailureDescription(error),
                    addressFamily: nil
                )
            }
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = timeout
        request.networkServiceType = .responsiveData
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")

        let start = Date()
        do {
            let (_, response) = try await BiliNetworkRetry.data(
                sessionProvider: { BiliPlaybackNetworkSessionPool.shared.playbackProbeSession() },
                request: request,
                policy: .playbackProbe
            )
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let didSucceed = (200..<400).contains(statusCode) || statusCode == 403
            return PlaybackCDNProbeResult(
                preference: preference,
                elapsedMilliseconds: elapsed,
                didSucceed: didSucceed,
                errorDescription: didSucceed ? nil : httpFailureDescription(statusCode: statusCode),
                addressFamily: addressFamilyPreference.requiredFamily
            )
        } catch {
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            return PlaybackCDNProbeResult(
                preference: preference,
                elapsedMilliseconds: elapsed,
                didSucceed: false,
                errorDescription: networkFailureDescription(error),
                addressFamily: addressFamilyPreference.requiredFamily
            )
        }
    }

    private static func httpFailureDescription(statusCode: Int) -> String {
        switch statusCode {
        case 0:
            return "未收到 HTTP 响应"
        case 400:
            return "请求参数异常（HTTP 400）"
        case 401:
            return "需要鉴权（HTTP 401）"
        case 404:
            return "探测资源不存在（HTTP 404）"
        case 408:
            return "CDN 响应超时（HTTP 408）"
        case 429:
            return "请求过于频繁（HTTP 429）"
        case 500...599:
            return "CDN 服务异常（HTTP \(statusCode)）"
        default:
            return "HTTP 状态异常（\(statusCode)）"
        }
    }

    private static func dnsFailureDescription(_ error: Error) -> String {
        if let error = error as? DNSResolutionError {
            return error.reasonDescription
        }
        return "DNS 解析失败：\(error.localizedDescription)"
    }

    private static func networkFailureDescription(_ error: Error) -> String {
        if error is CancellationError {
            return "测速已取消"
        }
        guard let urlError = error as? URLError else {
            return "连接失败：\(error.localizedDescription)"
        }

        switch urlError.code {
        case .timedOut:
            return "连接超时"
        case .cannotFindHost, .dnsLookupFailed:
            return "DNS 解析失败"
        case .cannotConnectToHost:
            return "无法连接到 CDN Host"
        case .networkConnectionLost:
            return "连接中断"
        case .notConnectedToInternet:
            return "当前网络不可用"
        case .cannotLoadFromNetwork:
            return "系统禁止从网络加载"
        case .secureConnectionFailed:
            return "TLS 握手失败"
        case .serverCertificateUntrusted,
             .serverCertificateHasBadDate,
             .serverCertificateNotYetValid,
             .serverCertificateHasUnknownRoot:
            return "证书校验失败"
        case .appTransportSecurityRequiresSecureConnection:
            return "ATS 安全策略拦截"
        case .badServerResponse:
            return "服务器响应异常"
        case .resourceUnavailable:
            return "资源不可用"
        case .cancelled:
            return "测速被取消"
        default:
            return "连接失败（\(urlError.code.rawValue)）"
        }
    }

    private static func quickProbeResults(
        addressFamilyPreference: PlaybackNetworkAddressFamilyPreference,
        timeout: TimeInterval
    ) async -> [PlaybackCDNProbeResult] {
        let clampedTimeout = min(max(timeout, 0.12), Self.timeout)
        return await withTaskGroup(of: PlaybackCDNProbeResult?.self) { group in
            for candidate in PlaybackCDNPreference.manualProbeCandidates {
                group.addTask(priority: .userInitiated) {
                    await probe(
                        candidate,
                        addressFamilyPreference: addressFamilyPreference,
                        timeout: clampedTimeout
                    )
                }
            }

            group.addTask(priority: .userInitiated) {
                try? await Task.sleep(nanoseconds: UInt64(clampedTimeout * 1_000_000_000))
                return nil
            }

            var results = [PlaybackCDNProbeResult]()
            while let result = await group.next() {
                guard let result else {
                    group.cancelAll()
                    break
                }
                results.append(result)
                if result.didSucceed && result.elapsedMilliseconds != nil {
                    group.cancelAll()
                    break
                }
            }
            return sortedResults(results)
        }
    }

    private static func sortedResults(_ results: [PlaybackCDNProbeResult]) -> [PlaybackCDNProbeResult] {
        results.sorted { lhs, rhs in
            if lhs.didSucceed != rhs.didSucceed {
                return lhs.didSucceed
            }
            switch (lhs.elapsedMilliseconds, rhs.elapsedMilliseconds) {
            case let (left?, right?):
                return left < right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return lhs.preference.title < rhs.preference.title
            }
        }
    }

    private static func resolvedAddressFamilies(for host: String) throws -> Set<PlaybackNetworkAddressFamily> {
        var hints = addrinfo(
            ai_flags: 0,
            ai_family: AF_UNSPEC,
            ai_socktype: 0,
            ai_protocol: 0,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, nil, &hints, &result)
        guard status == 0 else {
            throw DNSResolutionError(code: status)
        }
        defer {
            if let result {
                freeaddrinfo(result)
            }
        }

        var families = Set<PlaybackNetworkAddressFamily>()
        var pointer = result
        while let current = pointer {
            switch current.pointee.ai_family {
            case AF_INET:
                families.insert(.ipv4)
            case AF_INET6:
                families.insert(.ipv6)
            default:
                break
            }
            pointer = current.pointee.ai_next
        }
        return families
    }
}

private struct DNSResolutionError: LocalizedError {
    let code: Int32

    var errorDescription: String? {
        String(cString: gai_strerror(code))
    }

    var reasonDescription: String {
        switch code {
        case EAI_NONAME:
            return "DNS 未找到主机"
        case EAI_AGAIN:
            return "DNS 临时失败"
        case EAI_FAIL:
            return "DNS 查询失败"
        default:
            return "DNS 解析失败：\(errorDescription ?? "code \(code)")"
        }
    }
}
