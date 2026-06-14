import Foundation
import Network
import OSLog
import UIKit

nonisolated struct PlayURLCacheKey: Hashable, Sendable {
    let bvid: String
    let cid: Int
    let requestedQuality: Int
    let audioLanguage: String
    let fnval: String
    let fnver: String
    let platform: String
    let prefersProgressiveFastStart: Bool
    let supplementsQualities: Bool
}

nonisolated struct PlayURLCacheLoginScope: Hashable, Sendable {
    let isLoggedIn: Bool
    let userMID: Int?
    let guestModeEnabled: Bool
}

nonisolated struct PlayURLCacheStatistics: Sendable {
    let count: Int
    let capacity: Int
    let hits: Int
    let misses: Int
    let stores: Int
    let evictions: Int
    let invalidations: Int
}

nonisolated enum PlayURLMediaExpiration {
    static let safetyMargin: TimeInterval = 90
    static let minimumReusableLifetime: TimeInterval = 15

    static func expirationDate(for data: PlayURLData, storedAt: Date, fallbackTTL: TimeInterval) -> Date {
        let fallbackExpiration = storedAt.addingTimeInterval(fallbackTTL)
        guard let mediaExpiration = earliestMediaURLExpirationDate(in: data) else {
            return fallbackExpiration
        }
        return min(fallbackExpiration, mediaExpiration.addingTimeInterval(-safetyMargin))
    }

    static func isReusable(expirationDate: Date, now: Date = Date()) -> Bool {
        expirationDate.timeIntervalSince(now) > minimumReusableLifetime
    }

    private static func earliestMediaURLExpirationDate(in data: PlayURLData) -> Date? {
        mediaURLs(in: data)
            .compactMap(expirationDate(in:))
            .min()
    }

    private static func mediaURLs(in data: PlayURLData) -> [URL] {
        var urls = [URL]()
        func append(_ value: String?) {
            guard let value,
                  let url = URL(string: value)
            else { return }
            urls.append(url)
        }

        data.durl?.forEach { item in
            append(item.url)
            item.backupURL?.forEach(append)
        }
        data.dash?.video?.forEach { stream in
            append(stream.baseURL)
            stream.backupURL?.forEach(append)
        }
        data.dash?.audio?.forEach { stream in
            append(stream.baseURL)
            stream.backupURL?.forEach(append)
        }
        return urls
    }

    private static func expirationDate(in url: URL) -> Date? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems
        else { return nil }
        for item in queryItems {
            let key = item.name.lowercased()
            guard ["deadline", "expires", "expire", "expiration", "wstime"].contains(key),
                  let value = item.value,
                  let timestamp = timestamp(from: value, allowsHex: key == "wstime")
            else { continue }
            return Date(timeIntervalSince1970: timestamp)
        }
        return nil
    }

    private static func timestamp(from rawValue: String, allowsHex: Bool) -> TimeInterval? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let integerValue: Int64?
        if allowsHex,
           let hexValue = Int64(trimmed, radix: 16) {
            integerValue = hexValue
        } else {
            integerValue = Int64(trimmed)
        }
        guard let integerValue else { return nil }

        let seconds = integerValue > 10_000_000_000
            ? TimeInterval(integerValue) / 1000
            : TimeInterval(integerValue)
        guard seconds > 1_500_000_000,
              seconds < 4_102_444_800
        else { return nil }
        return seconds
    }
}

actor PlayURLCache {
    static let shared = PlayURLCache()

    private struct Entry {
        let data: PlayURLData
        let scope: PlayURLCacheLoginScope
        let storedAt: Date
        let expiresAt: Date
        var lastAccessedAt: Date
    }

    private let capacity: Int
    private let ttl: TimeInterval
    private var entries: [PlayURLCacheKey: Entry] = [:]
    private var hits = 0
    private var misses = 0
    private var stores = 0
    private var evictions = 0
    private var invalidations = 0

    init(capacity: Int = 80, ttl: TimeInterval = 10 * 60) {
        self.capacity = capacity
        self.ttl = ttl
    }

    func value(for key: PlayURLCacheKey, scope: PlayURLCacheLoginScope) -> PlayURLData? {
        trimExpired()
        guard var entry = entries[key] else {
            misses += 1
            return nil
        }
        guard entry.scope == scope else {
            entries[key] = nil
            misses += 1
            return nil
        }
        guard Date().timeIntervalSince(entry.storedAt) < ttl else {
            entries[key] = nil
            misses += 1
            return nil
        }
        guard PlayURLMediaExpiration.isReusable(expirationDate: entry.expiresAt) else {
            entries[key] = nil
            misses += 1
            return nil
        }
        entry.lastAccessedAt = Date()
        entries[key] = entry
        hits += 1
        return entry.data
    }

    func contains(_ key: PlayURLCacheKey, scope: PlayURLCacheLoginScope) -> Bool {
        value(for: key, scope: scope) != nil
    }

    func store(_ data: PlayURLData, for key: PlayURLCacheKey, scope: PlayURLCacheLoginScope) {
        guard shouldCache(data, scope: scope) else { return }
        let now = Date()
        let expiresAt = PlayURLMediaExpiration.expirationDate(for: data, storedAt: now, fallbackTTL: ttl)
        guard PlayURLMediaExpiration.isReusable(expirationDate: expiresAt, now: now) else { return }
        entries[key] = Entry(data: data, scope: scope, storedAt: now, expiresAt: expiresAt, lastAccessedAt: now)
        stores += 1
        trimIfNeeded()
    }

    func playableFallback(
        bvid: String,
        cid: Int,
        platform: String? = nil,
        scope: PlayURLCacheLoginScope
    ) -> PlayURLData? {
        trimExpired()
        let candidates = entries
            .filter { key, entry in
                key.bvid == bvid
                    && key.cid == cid
                    && (platform == nil || key.platform == platform)
                    && entry.scope == scope
                    && entry.data.hasPlayableStreamPayload
            }
            .sorted { lhs, rhs in
                if lhs.value.data.highestPlayableQuality == rhs.value.data.highestPlayableQuality {
                    return lhs.value.lastAccessedAt > rhs.value.lastAccessedAt
                }
                return lhs.value.data.highestPlayableQuality > rhs.value.data.highestPlayableQuality
            }
        guard let candidate = candidates.first else {
            misses += 1
            return nil
        }
        var entry = candidate.value
        entry.lastAccessedAt = Date()
        entries[candidate.key] = entry
        hits += 1
        return entry.data
    }

    func invalidate(bvid: String) {
        let oldCount = entries.count
        entries = entries.filter { $0.key.bvid != bvid }
        invalidations += max(0, oldCount - entries.count)
    }

    func invalidateForLoginStateChange() {
        invalidations += entries.count
        entries.removeAll()
    }

    func clearMemoryCache() {
        evictions += entries.count
        entries.removeAll()
    }

    func statistics() -> PlayURLCacheStatistics {
        trimExpired()
        return PlayURLCacheStatistics(
            count: entries.count,
            capacity: capacity,
            hits: hits,
            misses: misses,
            stores: stores,
            evictions: evictions,
            invalidations: invalidations
        )
    }

    private func shouldCache(_ data: PlayURLData, scope: PlayURLCacheLoginScope) -> Bool {
        guard scope.isLoggedIn, !scope.guestModeEnabled else { return false }
        guard data.hasPlayableStreamPayload else { return false }
        if let code = data.code, code != 0 { return false }
        if let quality = data.quality, quality <= 0, data.highestPlayableQuality <= 0 { return false }
        return true
    }

    private func trimExpired(now: Date = Date()) {
        let oldCount = entries.count
        entries = entries.filter {
            now.timeIntervalSince($0.value.storedAt) < ttl
                && PlayURLMediaExpiration.isReusable(expirationDate: $0.value.expiresAt, now: now)
        }
        evictions += max(0, oldCount - entries.count)
    }

    private func trimIfNeeded() {
        trimExpired()
        guard entries.count > capacity else { return }
        let keptKeys = Set(
            entries
                .sorted { $0.value.lastAccessedAt > $1.value.lastAccessedAt }
                .prefix(capacity)
                .map(\.key)
        )
        let oldCount = entries.count
        entries = entries.filter { keptKeys.contains($0.key) }
        evictions += max(0, oldCount - entries.count)
    }
}

nonisolated enum BiliURLSessionFactory {
    static let mobileUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"
    static let webUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    static let imageUserAgent = mobileUserAgent
    static let responseCompressionHeader = "br, gzip, deflate"

    private static let apiURLCache = URLCache(
        memoryCapacity: 32 * 1024 * 1024,
        diskCapacity: 96 * 1024 * 1024,
        directory: URL.cachesDirectory.appending(path: "BiliAPICache", directoryHint: .isDirectory)
    )

    static let imageURLCache = URLCache(
        memoryCapacity: 32 * 1024 * 1024,
        diskCapacity: 512 * 1024 * 1024,
        directory: URL.cachesDirectory.appending(path: "BiliRemoteImageCache", directoryHint: .isDirectory)
    )

    static func makeAPISession(delegate: URLSessionDelegate? = nil) -> URLSession {
        let configuration = makeAPIConfiguration()
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    static func makeAPIConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.urlCache = apiURLCache
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.waitsForConnectivity = true
        configuration.networkServiceType = .responsiveData
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 40
        configuration.httpAdditionalHeaders = [
            "User-Agent": mobileUserAgent,
            "Accept": "application/json, text/plain, */*",
            "Accept-Encoding": responseCompressionHeader,
            "Accept-Language": "zh-CN,zh;q=0.9"
        ]
        return configuration
    }

    static func makeImageSession() -> URLSession {
        URLSession(configuration: makeImageConfiguration())
    }

    static func makeImageConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.urlCache = imageURLCache
        configuration.httpMaximumConnectionsPerHost = 8
        configuration.waitsForConnectivity = true
        configuration.networkServiceType = .responsiveData
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 24
        configuration.httpAdditionalHeaders = imageHeaders()
        return configuration
    }

    static func makePlaybackResourceSession(delegateQueue: OperationQueue? = nil) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.waitsForConnectivity = true
        configuration.networkServiceType = .video
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 60
        configuration.httpAdditionalHeaders = playbackHeaders(referer: "https://www.bilibili.com/", cookieHeader: nil)
        return URLSession(configuration: configuration, delegate: nil, delegateQueue: delegateQueue)
    }

    static func makePlaybackDataSession() -> URLSession {
        URLSession(configuration: makePlaybackDataConfiguration(), delegate: nil, delegateQueue: nil)
    }

    static func makePlaybackDataConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpMaximumConnectionsPerHost = 8
        configuration.waitsForConnectivity = false
        configuration.networkServiceType = .video
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 20
        configuration.httpAdditionalHeaders = playbackHeaders(referer: "https://www.bilibili.com/", cookieHeader: nil)
        return configuration
    }

    static func makePlaybackStreamingConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpMaximumConnectionsPerHost = 8
        configuration.waitsForConnectivity = false
        configuration.networkServiceType = .video
        configuration.timeoutIntervalForRequest = 4
        configuration.timeoutIntervalForResource = 18
        configuration.httpAdditionalHeaders = playbackHeaders(referer: "https://www.bilibili.com/", cookieHeader: nil)
        return configuration
    }

    static func makePlaybackProbeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpMaximumConnectionsPerHost = 8
        configuration.waitsForConnectivity = false
        configuration.networkServiceType = .responsiveData
        configuration.timeoutIntervalForRequest = 0.8
        configuration.timeoutIntervalForResource = 2
        configuration.httpAdditionalHeaders = [
            "User-Agent": mobileUserAgent,
            "Accept": "*/*",
            "Accept-Encoding": responseCompressionHeader,
            "Accept-Language": "zh-CN,zh;q=0.9",
            "Referer": "https://www.bilibili.com/"
        ]
        return URLSession(configuration: configuration, delegate: nil, delegateQueue: nil)
    }

    static func apiCacheStatistics() -> URLCacheStatistics {
        URLCacheStatistics(
            memoryUsage: apiURLCache.currentMemoryUsage,
            memoryCapacity: apiURLCache.memoryCapacity,
            diskUsage: apiURLCache.currentDiskUsage,
            diskCapacity: apiURLCache.diskCapacity
        )
    }

    static func clearAPICache() {
        apiURLCache.removeAllCachedResponses()
    }

    static func apiHeaders(referer: String, userAgent: String?, cookieHeader: String) -> [String: String] {
        [
            "User-Agent": userAgent ?? mobileUserAgent,
            "Referer": referer,
            "Origin": "https://www.bilibili.com",
            "Accept": "application/json, text/plain, */*",
            "Accept-Language": "zh-CN,zh;q=0.9",
            "Accept-Encoding": responseCompressionHeader,
            "Cookie": cookieHeader
        ]
    }

    static func imageHeaders() -> [String: String] {
        [
            "Referer": "https://www.bilibili.com/",
            "User-Agent": imageUserAgent,
            "Accept": "image/avif,image/webp,image/apng,image/*,*/*;q=0.8",
            "Accept-Encoding": responseCompressionHeader,
            "Accept-Language": "zh-CN,zh;q=0.9"
        ]
    }

    static func playbackHeaders(referer: String, cookieHeader: String?) -> [String: String] {
        var headers = [
            "User-Agent": mobileUserAgent,
            "Referer": referer,
            "Accept": "*/*",
            "Accept-Encoding": responseCompressionHeader,
            "Accept-Language": "zh-CN,zh;q=0.9"
        ]
        if let cookieHeader, !cookieHeader.isEmpty {
            headers["Cookie"] = cookieHeader
        }
        return headers
    }
}

nonisolated struct URLCacheStatistics: Sendable {
    let memoryUsage: Int
    let memoryCapacity: Int
    let diskUsage: Int
    let diskCapacity: Int
}

nonisolated struct BiliNetworkRetryPolicy: Sendable {
    let label: String
    let attempts: Int
    let baseDelayNanoseconds: UInt64
    let maxDelayNanoseconds: UInt64
    let jitterNanoseconds: UInt64
    let retryStatusCodes: Set<Int>
    let retryMethods: Set<String>
    let retriesEmptyData: Bool

    init(
        label: String = "custom",
        attempts: Int,
        baseDelayNanoseconds: UInt64,
        maxDelayNanoseconds: UInt64,
        jitterNanoseconds: UInt64,
        retryStatusCodes: Set<Int> = Self.defaultRetryStatusCodes,
        retryMethods: Set<String> = Self.defaultRetryMethods,
        retriesEmptyData: Bool = false
    ) {
        self.label = label
        self.attempts = max(1, attempts)
        self.baseDelayNanoseconds = baseDelayNanoseconds
        self.maxDelayNanoseconds = max(baseDelayNanoseconds, maxDelayNanoseconds)
        self.jitterNanoseconds = jitterNanoseconds
        self.retryStatusCodes = retryStatusCodes
        self.retryMethods = retryMethods
        self.retriesEmptyData = retriesEmptyData
    }

    static let api = BiliNetworkRetryPolicy(
        label: "api",
        attempts: 2,
        baseDelayNanoseconds: 120_000_000,
        maxDelayNanoseconds: 260_000_000,
        jitterNanoseconds: 60_000_000,
        retriesEmptyData: true
    )

    static let image = BiliNetworkRetryPolicy(
        label: "image",
        attempts: 2,
        baseDelayNanoseconds: 70_000_000,
        maxDelayNanoseconds: 180_000_000,
        jitterNanoseconds: 50_000_000
    )

    static let playbackProbe = BiliNetworkRetryPolicy(
        label: "playbackProbe",
        attempts: 2,
        baseDelayNanoseconds: 45_000_000,
        maxDelayNanoseconds: 120_000_000,
        jitterNanoseconds: 35_000_000
    )

    static let playbackShortResource = BiliNetworkRetryPolicy(
        label: "playbackShortResource",
        attempts: 2,
        baseDelayNanoseconds: 90_000_000,
        maxDelayNanoseconds: 220_000_000,
        jitterNanoseconds: 60_000_000,
        retriesEmptyData: true
    )

    private static let defaultRetryMethods: Set<String> = ["GET", "HEAD", "OPTIONS"]
    private static let defaultRetryStatusCodes: Set<Int> = [
        408, 425, 429, 500, 502, 503, 504, 522, 523, 524
    ]

    func delayNanoseconds(afterFailureAt attemptIndex: Int) -> UInt64 {
        let multiplier = UInt64(max(attemptIndex + 1, 1))
        let scaledDelay = min(maxDelayNanoseconds, baseDelayNanoseconds * multiplier)
        let jitter = jitterNanoseconds > 0 ? UInt64.random(in: 0...jitterNanoseconds) : 0
        return min(maxDelayNanoseconds, scaledDelay + jitter)
    }

    func canRetry(_ request: URLRequest) -> Bool {
        let method = (request.httpMethod ?? "GET").uppercased()
        return retryMethods.contains(method)
    }

    func shouldRetry(statusCode: Int) -> Bool {
        retryStatusCodes.contains(statusCode)
    }
}

nonisolated enum BiliNetworkRetry {
    static func data(
        session: URLSession,
        request: URLRequest,
        priority: Float = URLSessionTask.defaultPriority,
        policy: BiliNetworkRetryPolicy
    ) async throws -> (Data, URLResponse) {
        try await data(
            sessionProvider: { session },
            request: request,
            priority: priority,
            policy: policy
        )
    }

    static func data(
        sessionProvider: @escaping @Sendable () -> URLSession,
        request: URLRequest,
        priority: Float = URLSessionTask.defaultPriority,
        policy: BiliNetworkRetryPolicy
    ) async throws -> (Data, URLResponse) {
        let canRetryRequest = policy.canRetry(request)
        var lastError: Error?
        let startedAt = Date()

        for attempt in 0..<policy.attempts {
            try Task.checkCancellation()
            do {
                let (data, response) = try await dataOnce(
                    session: sessionProvider(),
                    request: request,
                    priority: priority
                )
                if canRetryRequest,
                   attempt < policy.attempts - 1,
                   let reason = retryReason(data: data, response: response, policy: policy) {
                    let delay = policy.delayNanoseconds(afterFailureAt: attempt)
                    logRetry(
                        policy: policy,
                        request: request,
                        attempt: attempt,
                        reason: reason,
                        startedAt: startedAt,
                        delayNanoseconds: delay
                    )
                    try await sleepBeforeRetry(delayNanoseconds: delay)
                    continue
                }
                return (data, response)
            } catch {
                guard canRetryRequest,
                      attempt < policy.attempts - 1,
                      let reason = retryReason(error: error)
                else {
                    if !(error is CancellationError),
                       (error as? URLError)?.code != .cancelled {
                        logFinalFailure(
                            policy: policy,
                            request: request,
                            attempt: attempt,
                            error: error,
                            startedAt: startedAt
                        )
                    }
                    throw error
                }
                lastError = error
                let delay = policy.delayNanoseconds(afterFailureAt: attempt)
                logRetry(
                    policy: policy,
                    request: request,
                    attempt: attempt,
                    reason: reason,
                    startedAt: startedAt,
                    delayNanoseconds: delay
                )
                try await sleepBeforeRetry(delayNanoseconds: delay)
            }
        }

        throw lastError ?? URLError(.unknown)
    }

    private static func dataOnce(
        session: URLSession,
        request: URLRequest,
        priority: Float
    ) async throws -> (Data, URLResponse) {
        let taskBox = BiliNetworkURLSessionTaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: request) { data, response, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let data, let response else {
                        continuation.resume(throwing: URLError(.badServerResponse))
                        return
                    }
                    continuation.resume(returning: (data, response))
                }
                task.priority = priority
                taskBox.task = task
                task.resume()
            }
        } onCancel: {
            taskBox.cancel()
        }
    }

    private static func retryReason(
        data: Data,
        response: URLResponse,
        policy: BiliNetworkRetryPolicy
    ) -> String? {
        if policy.retriesEmptyData, data.isEmpty {
            return "emptyData"
        }
        guard let httpResponse = response as? HTTPURLResponse else { return nil }
        guard policy.shouldRetry(statusCode: httpResponse.statusCode) else { return nil }
        return "status=\(httpResponse.statusCode)"
    }

    private static func retryReason(error: Error) -> String? {
        if error is CancellationError {
            return nil
        }
        guard let urlError = error as? URLError else {
            return nil
        }
        switch urlError.code {
        case .cancelled:
            return nil
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .networkConnectionLost,
             .notConnectedToInternet,
             .cannotLoadFromNetwork,
             .badServerResponse,
             .resourceUnavailable:
            return "urlError=\(urlError.code.rawValue)"
        default:
            return nil
        }
    }

    private static func logRetry(
        policy: BiliNetworkRetryPolicy,
        request: URLRequest,
        attempt: Int,
        reason: String,
        startedAt: Date,
        delayNanoseconds: UInt64
    ) {
        let delayMilliseconds = Double(delayNanoseconds) / 1_000_000
        PlayerMetricsLog.logger.info(
            "networkRetry policy=\(policy.label, privacy: .public) attempt=\(attempt + 1, privacy: .public)/\(policy.attempts, privacy: .public) reason=\(reason, privacy: .public) method=\(request.httpMethod ?? "GET", privacy: .public) host=\(request.url?.host ?? "-", privacy: .public) path=\(diagnosticPath(for: request.url), privacy: .public) elapsedMs=\(elapsedMilliseconds(since: startedAt), privacy: .public) delayMs=\(Int(delayMilliseconds.rounded()), privacy: .public)"
        )
    }

    private static func logFinalFailure(
        policy: BiliNetworkRetryPolicy,
        request: URLRequest,
        attempt: Int,
        error: Error,
        startedAt: Date
    ) {
        PlayerMetricsLog.logger.error(
            "networkRetryFinalFailure policy=\(policy.label, privacy: .public) attempt=\(attempt + 1, privacy: .public)/\(policy.attempts, privacy: .public) method=\(request.httpMethod ?? "GET", privacy: .public) host=\(request.url?.host ?? "-", privacy: .public) path=\(diagnosticPath(for: request.url), privacy: .public) elapsedMs=\(elapsedMilliseconds(since: startedAt), privacy: .public) error=\(String(describing: error), privacy: .public)"
        )
    }

    private static func elapsedMilliseconds(since start: Date) -> Int {
        max(0, Int((Date().timeIntervalSince(start) * 1000).rounded()))
    }

    private static func diagnosticPath(for url: URL?) -> String {
        guard let url else { return "-" }
        if url.host?.contains("bilibili.com") == true {
            switch url.path {
            case "/x/player/playurl", "/x/player/wbi/playurl":
                return "playurl"
            case "/x/web-interface/view":
                return "detail"
            case "/x/web-interface/archive/related":
                return "related"
            default:
                break
            }
        }
        return url.path.isEmpty ? "/" : url.path
    }

    private static func sleepBeforeRetry(
        delayNanoseconds: UInt64
    ) async throws {
        guard delayNanoseconds > 0 else { return }
        try await Task.sleep(nanoseconds: delayNanoseconds)
    }
}

private nonisolated final class BiliNetworkURLSessionTaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _task: URLSessionTask?
    private var isCancelled = false

    var task: URLSessionTask? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _task
        }
        set {
            lock.lock()
            _task = newValue
            let shouldCancel = isCancelled
            lock.unlock()
            if shouldCancel {
                newValue?.cancel()
            }
        }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let task = _task
        lock.unlock()
        task?.cancel()
    }
}

nonisolated final class BiliPlaybackNetworkSessionPool: @unchecked Sendable {
    static let shared = BiliPlaybackNetworkSessionPool()

    private let lock = NSLock()
    private var dataSession = BiliURLSessionFactory.makePlaybackDataSession()
    private var probeSession = BiliURLSessionFactory.makePlaybackProbeSession()

    private init() {}

    func playbackDataSession() -> URLSession {
        lock.lock()
        let session = dataSession
        lock.unlock()
        return session
    }

    func playbackProbeSession() -> URLSession {
        lock.lock()
        let session = probeSession
        lock.unlock()
        return session
    }

    func refreshForNetworkPathChange() {
        let oldDataSession: URLSession
        let oldProbeSession: URLSession
        lock.lock()
        oldDataSession = dataSession
        oldProbeSession = probeSession
        dataSession = BiliURLSessionFactory.makePlaybackDataSession()
        probeSession = BiliURLSessionFactory.makePlaybackProbeSession()
        lock.unlock()

        oldDataSession.finishTasksAndInvalidate()
        oldProbeSession.finishTasksAndInvalidate()
    }
}

nonisolated struct BiliAPIResponseCachePolicy: Sendable {
    let freshTTL: TimeInterval
    let staleTTL: TimeInterval

    init(freshTTL: TimeInterval, staleTTL: TimeInterval) {
        self.freshTTL = max(0, freshTTL)
        self.staleTTL = max(self.freshTTL, staleTTL)
    }

    static let brief = BiliAPIResponseCachePolicy(freshTTL: 30, staleTTL: 5 * 60)
    static let short = BiliAPIResponseCachePolicy(freshTTL: 90, staleTTL: 10 * 60)
    static let detail = BiliAPIResponseCachePolicy(freshTTL: 5 * 60, staleTTL: 60 * 60)
    static let long = BiliAPIResponseCachePolicy(freshTTL: 30 * 60, staleTTL: 6 * 60 * 60)
}

nonisolated struct BiliAPIResponseMemoryCacheStatistics: Sendable {
    let count: Int
    let estimatedBytes: Int
    let byteCapacity: Int
    let freshCount: Int
    let staleCount: Int
    let hits: Int
    let staleHits: Int
    let misses: Int
    let stores: Int
    let evictions: Int
}

actor BiliAPIResponseMemoryCache {
    static let shared = BiliAPIResponseMemoryCache()

    private struct Entry {
        let data: Data
        let freshUntil: Date
        let staleUntil: Date
        var lastAccessedAt: Date
    }

    private let maxEntries = 128
    private let maxBytes = 8 * 1024 * 1024
    private var entries: [String: Entry] = [:]
    private var estimatedBytes = 0
    private var hits = 0
    private var staleHits = 0
    private var misses = 0
    private var stores = 0
    private var evictions = 0

    func freshData(for key: String) -> Data? {
        data(for: key, allowingStale: false)
    }

    func staleData(for key: String) -> Data? {
        data(for: key, allowingStale: true)
    }

    func store(_ data: Data, for key: String, policy: BiliAPIResponseCachePolicy) {
        guard policy.freshTTL > 0, !data.isEmpty, data.count <= maxBytes / 2 else { return }
        let now = Date()
        if let existing = entries[key] {
            estimatedBytes -= existing.data.count
        }
        stores += 1
        entries[key] = Entry(
            data: data,
            freshUntil: now.addingTimeInterval(policy.freshTTL),
            staleUntil: now.addingTimeInterval(policy.staleTTL),
            lastAccessedAt: now
        )
        estimatedBytes += data.count
        trimIfNeeded(now: now)
        ResourceCacheAutoTrim.schedule()
    }

    func clear() {
        entries.removeAll()
        estimatedBytes = 0
        hits = 0
        staleHits = 0
        misses = 0
        stores = 0
        evictions = 0
    }

    func statistics() -> BiliAPIResponseMemoryCacheStatistics {
        let now = Date()
        trimIfNeeded(now: now)
        var freshCount = 0
        var staleCount = 0
        for entry in entries.values {
            if entry.freshUntil >= now {
                freshCount += 1
            } else if entry.staleUntil >= now {
                staleCount += 1
            }
        }
        return BiliAPIResponseMemoryCacheStatistics(
            count: entries.count,
            estimatedBytes: estimatedBytes,
            byteCapacity: maxBytes,
            freshCount: freshCount,
            staleCount: staleCount,
            hits: hits,
            staleHits: staleHits,
            misses: misses,
            stores: stores,
            evictions: evictions
        )
    }

    private func data(for key: String, allowingStale: Bool) -> Data? {
        let now = Date()
        guard var entry = entries[key] else {
            misses += 1
            return nil
        }
        let expiry = allowingStale ? entry.staleUntil : entry.freshUntil
        guard expiry >= now else {
            estimatedBytes -= entry.data.count
            entries[key] = nil
            misses += 1
            evictions += 1
            return nil
        }
        entry.lastAccessedAt = now
        entries[key] = entry
        if allowingStale, entry.freshUntil < now {
            staleHits += 1
        } else {
            hits += 1
        }
        return entry.data
    }

    private func trimIfNeeded(now: Date = Date()) {
        for (key, entry) in entries where entry.staleUntil < now {
            estimatedBytes -= entry.data.count
            entries[key] = nil
            evictions += 1
        }

        guard entries.count > maxEntries || estimatedBytes > maxBytes else { return }
        for key in entries
            .sorted(by: { $0.value.lastAccessedAt < $1.value.lastAccessedAt })
            .map(\.key) {
            guard entries.count > maxEntries || estimatedBytes > maxBytes else { break }
            if let removed = entries.removeValue(forKey: key) {
                estimatedBytes -= removed.data.count
                evictions += 1
            }
        }
    }
}

nonisolated struct ProgressiveMediaCacheKey: Hashable, Sendable {
    let url: String
    let rangeHeader: String
}

nonisolated struct ProgressiveMediaCacheResponse: Sendable {
    let data: Data
    let contentLength: Int64
    let mimeType: String?
    let isByteRangeAccessSupported: Bool
}

nonisolated struct ProgressiveMediaCacheStatistics: Sendable {
    let entryCount: Int
    let estimatedBytes: Int
    let byteCapacity: Int
    let hits: Int
    let misses: Int
    let stores: Int
    let evictions: Int
}

actor ProgressiveMediaSegmentCache {
    static let shared = ProgressiveMediaSegmentCache()

    private struct Entry {
        let response: ProgressiveMediaCacheResponse
        let bytes: Int
        let storedAt: Date
        var lastAccessedAt: Date
    }

    private let byteCapacity: Int
    private let itemLimit: Int
    private let maxEntryBytes: Int
    private let ttl: TimeInterval
    private var entries: [ProgressiveMediaCacheKey: Entry] = [:]
    private var estimatedBytes = 0
    private var hits = 0
    private var misses = 0
    private var stores = 0
    private var evictions = 0

    init(
        byteCapacity: Int = 24 * 1024 * 1024,
        itemLimit: Int = 96,
        maxEntryBytes: Int = 2 * 1024 * 1024,
        ttl: TimeInterval = 15 * 60
    ) {
        self.byteCapacity = byteCapacity
        self.itemLimit = itemLimit
        self.maxEntryBytes = maxEntryBytes
        self.ttl = ttl
    }

    func response(for key: ProgressiveMediaCacheKey) -> ProgressiveMediaCacheResponse? {
        trimExpired()
        guard var entry = entries[key] else {
            misses += 1
            return nil
        }
        entry.lastAccessedAt = Date()
        entries[key] = entry
        hits += 1
        return entry.response
    }

    func store(_ response: ProgressiveMediaCacheResponse, for key: ProgressiveMediaCacheKey) {
        let bytes = response.data.count
        guard bytes > 0, bytes <= maxEntryBytes else { return }
        if let existing = entries[key] {
            estimatedBytes -= existing.bytes
        }
        let now = Date()
        entries[key] = Entry(response: response, bytes: bytes, storedAt: now, lastAccessedAt: now)
        estimatedBytes += bytes
        stores += 1
        trimIfNeeded()
        ResourceCacheAutoTrim.schedule()
    }

    func clear() {
        evictions += entries.count
        entries.removeAll()
        estimatedBytes = 0
    }

    func statistics() -> ProgressiveMediaCacheStatistics {
        trimExpired()
        return ProgressiveMediaCacheStatistics(
            entryCount: entries.count,
            estimatedBytes: estimatedBytes,
            byteCapacity: byteCapacity,
            hits: hits,
            misses: misses,
            stores: stores,
            evictions: evictions
        )
    }

    private func trimExpired(now: Date = Date()) {
        for (key, entry) in entries where now.timeIntervalSince(entry.storedAt) >= ttl {
            entries[key] = nil
            estimatedBytes -= entry.bytes
            evictions += 1
        }
        estimatedBytes = max(0, estimatedBytes)
    }

    private func trimIfNeeded() {
        trimExpired()
        while entries.count > itemLimit || estimatedBytes > byteCapacity {
            guard let oldest = entries.min(by: { $0.value.lastAccessedAt < $1.value.lastAccessedAt }) else { break }
            estimatedBytes -= oldest.value.bytes
            entries[oldest.key] = nil
            evictions += 1
        }
        estimatedBytes = max(0, estimatedBytes)
    }
}

nonisolated struct RemoteImageCacheStatistics: Sendable {
    let memoryEntryCount: Int
    let inFlightCount: Int
    let memoryCostLimit: Int
    let diskUsage: Int
    let diskCapacity: Int
    let hits: Int
    let misses: Int
    let stores: Int
    let evictions: Int
}

nonisolated struct SubtitleCueCacheKey: Hashable, Sendable {
    let bvid: String
    let cid: Int
    let subtitleId: String
    let language: String
    let urlHash: String
}

nonisolated struct DanmakuSegmentCacheKey: Hashable, Sendable {
    let cid: Int
    let segmentIndex: Int
}

nonisolated struct TimedResourceCacheStatistics: Sendable {
    let subtitleCount: Int
    let danmakuSegmentCount: Int
    let estimatedBytes: Int
    let byteCapacity: Int
    let hits: Int
    let misses: Int
    let evictions: Int
}

actor SubtitleDanmakuResourceCache {
    static let shared = SubtitleDanmakuResourceCache()

    private struct SubtitleEntry {
        let data: Data
        let bytes: Int
        let storedAt: Date
        var lastAccessedAt: Date
    }

    private struct DanmakuEntry {
        let items: [DanmakuItem]
        let bytes: Int
        let storedAt: Date
        var lastAccessedAt: Date
    }

    private let ttl: TimeInterval
    private let subtitleLimit: Int
    private let danmakuLimit: Int
    private let byteCapacity: Int
    private var subtitles: [SubtitleCueCacheKey: SubtitleEntry] = [:]
    private var danmakuSegments: [DanmakuSegmentCacheKey: DanmakuEntry] = [:]
    private var estimatedBytes = 0
    private var hits = 0
    private var misses = 0
    private var evictions = 0

    init(
        ttl: TimeInterval = 30 * 60,
        subtitleLimit: Int = 32,
        danmakuLimit: Int = 24,
        byteCapacity: Int = 3 * 1024 * 1024
    ) {
        self.ttl = ttl
        self.subtitleLimit = subtitleLimit
        self.danmakuLimit = danmakuLimit
        self.byteCapacity = byteCapacity
    }

    func subtitleData(for key: SubtitleCueCacheKey) -> Data? {
        trimExpired()
        guard var entry = subtitles[key] else {
            misses += 1
            return nil
        }
        entry.lastAccessedAt = Date()
        subtitles[key] = entry
        hits += 1
        return entry.data
    }

    func storeSubtitleData(_ data: Data, for key: SubtitleCueCacheKey) {
        guard !data.isEmpty else { return }
        if let existing = subtitles[key] {
            estimatedBytes -= existing.bytes
        }
        let now = Date()
        subtitles[key] = SubtitleEntry(data: data, bytes: data.count, storedAt: now, lastAccessedAt: now)
        estimatedBytes += data.count
        trimIfNeeded()
        ResourceCacheAutoTrim.schedule()
    }

    func danmaku(for cid: Int, segmentIndex: Int = 1) -> [DanmakuItem]? {
        trimExpired()
        let key = DanmakuSegmentCacheKey(cid: cid, segmentIndex: segmentIndex)
        guard var entry = danmakuSegments[key] else {
            misses += 1
            return nil
        }
        entry.lastAccessedAt = Date()
        danmakuSegments[key] = entry
        hits += 1
        return entry.items
    }

    func storeDanmaku(_ items: [DanmakuItem], for cid: Int, segmentIndex: Int = 1) {
        let key = DanmakuSegmentCacheKey(cid: cid, segmentIndex: segmentIndex)
        let bytes = Self.estimatedDanmakuBytes(items)
        if let existing = danmakuSegments[key] {
            estimatedBytes -= existing.bytes
        }
        let now = Date()
        danmakuSegments[key] = DanmakuEntry(items: items, bytes: bytes, storedAt: now, lastAccessedAt: now)
        estimatedBytes += bytes
        trimIfNeeded()
        ResourceCacheAutoTrim.schedule()
    }

    func clear() {
        evictions += subtitles.count + danmakuSegments.count
        subtitles.removeAll()
        danmakuSegments.removeAll()
        estimatedBytes = 0
    }

    func statistics() -> TimedResourceCacheStatistics {
        trimExpired()
        return TimedResourceCacheStatistics(
            subtitleCount: subtitles.count,
            danmakuSegmentCount: danmakuSegments.count,
            estimatedBytes: estimatedBytes,
            byteCapacity: byteCapacity,
            hits: hits,
            misses: misses,
            evictions: evictions
        )
    }

    private func trimExpired(now: Date = Date()) {
        for (key, entry) in subtitles where now.timeIntervalSince(entry.storedAt) >= ttl {
            subtitles[key] = nil
            estimatedBytes -= entry.bytes
            evictions += 1
        }
        for (key, entry) in danmakuSegments where now.timeIntervalSince(entry.storedAt) >= ttl {
            danmakuSegments[key] = nil
            estimatedBytes -= entry.bytes
            evictions += 1
        }
        estimatedBytes = max(0, estimatedBytes)
    }

    private func trimIfNeeded() {
        trimExpired()
        trimSubtitleCount()
        trimDanmakuCount()
        while estimatedBytes > byteCapacity {
            guard evictLeastRecentlyUsed() else { break }
        }
    }

    private func trimSubtitleCount() {
        guard subtitles.count > subtitleLimit else { return }
        let overflow = subtitles.count - subtitleLimit
        let keys = subtitles.sorted { $0.value.lastAccessedAt < $1.value.lastAccessedAt }
            .prefix(overflow)
            .map(\.key)
        keys.forEach { key in
            if let entry = subtitles.removeValue(forKey: key) {
                estimatedBytes -= entry.bytes
                evictions += 1
            }
        }
    }

    private func trimDanmakuCount() {
        guard danmakuSegments.count > danmakuLimit else { return }
        let overflow = danmakuSegments.count - danmakuLimit
        let keys = danmakuSegments.sorted { $0.value.lastAccessedAt < $1.value.lastAccessedAt }
            .prefix(overflow)
            .map(\.key)
        keys.forEach { key in
            if let entry = danmakuSegments.removeValue(forKey: key) {
                estimatedBytes -= entry.bytes
                evictions += 1
            }
        }
    }

    private func evictLeastRecentlyUsed() -> Bool {
        let subtitleCandidate = subtitles.min { $0.value.lastAccessedAt < $1.value.lastAccessedAt }
        let danmakuCandidate = danmakuSegments.min { $0.value.lastAccessedAt < $1.value.lastAccessedAt }
        switch (subtitleCandidate, danmakuCandidate) {
        case let (.some(subtitle), .some(danmaku)):
            if subtitle.value.lastAccessedAt <= danmaku.value.lastAccessedAt {
                estimatedBytes -= subtitle.value.bytes
                subtitles[subtitle.key] = nil
            } else {
                estimatedBytes -= danmaku.value.bytes
                danmakuSegments[danmaku.key] = nil
            }
        case let (.some(subtitle), nil):
            estimatedBytes -= subtitle.value.bytes
            subtitles[subtitle.key] = nil
        case let (nil, .some(danmaku)):
            estimatedBytes -= danmaku.value.bytes
            danmakuSegments[danmaku.key] = nil
        case (nil, nil):
            return false
        }
        evictions += 1
        estimatedBytes = max(0, estimatedBytes)
        return true
    }

    private static func estimatedDanmakuBytes(_ items: [DanmakuItem]) -> Int {
        items.reduce(0) { partialResult, item in
            partialResult + item.text.utf8.count + 48
        }
    }
}

actor ResourceRequestLimiter {
    static let shared = ResourceRequestLimiter()

    private let maxConcurrentDanmakuLoads = 2
    private var activeDanmakuLoads = 0
    private var danmakuWaiters: [CheckedContinuation<Void, Never>] = []

    func runDanmaku<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        await acquireDanmakuSlot()
        defer { releaseDanmakuSlot() }
        return try await operation()
    }

    private func acquireDanmakuSlot() async {
        if activeDanmakuLoads < maxConcurrentDanmakuLoads {
            activeDanmakuLoads += 1
            return
        }
        await withCheckedContinuation { continuation in
            danmakuWaiters.append(continuation)
        }
        activeDanmakuLoads += 1
    }

    private func releaseDanmakuSlot() {
        activeDanmakuLoads = max(0, activeDanmakuLoads - 1)
        guard !danmakuWaiters.isEmpty else { return }
        let waiter = danmakuWaiters.removeFirst()
        waiter.resume()
    }
}

nonisolated struct ResourceCacheSummary: Sendable {
    let playURL: PlayURLCacheStatistics
    let image: RemoteImageCacheStatistics
    let api: URLCacheStatistics
    let apiMemory: BiliAPIResponseMemoryCacheStatistics
    let videoRangeMedia: VideoRangeCacheStatistics
    let progressiveMedia: ProgressiveMediaCacheStatistics
    let subtitlesAndDanmaku: TimedResourceCacheStatistics

    var managedBytes: Int {
        [
            image.diskUsage,
            api.diskUsage,
            apiMemory.estimatedBytes,
            videoRangeMedia.estimatedBytes,
            progressiveMedia.estimatedBytes,
            subtitlesAndDanmaku.estimatedBytes
        ].reduce(0) { partial, value in
            partial + max(0, value)
        }
    }
}

nonisolated enum ResourceCacheLimitSettings {
    static let isEnabledKey = "ResourceCacheLimitSettings.isEnabled"
    static let megabytesKey = "ResourceCacheLimitSettings.limitMegabytes"
    static let defaultIsEnabled = true
    static let defaultLimitMegabytes = 1024
    static let minimumLimitMegabytes = 256
    static let maximumLimitMegabytes = 4096
    static let limitStepMegabytes = 256

    static var isEnabled: Bool {
        guard UserDefaults.standard.object(forKey: isEnabledKey) != nil else {
            return defaultIsEnabled
        }
        return UserDefaults.standard.bool(forKey: isEnabledKey)
    }

    static var limitMegabytes: Int {
        let stored = UserDefaults.standard.integer(forKey: megabytesKey)
        let rawValue = stored > 0 ? stored : defaultLimitMegabytes
        return clampedMegabytes(rawValue)
    }

    static var limitBytes: Int? {
        guard isEnabled else { return nil }
        return limitMegabytes * 1024 * 1024
    }

    static func clampedMegabytes(_ value: Int) -> Int {
        min(max(value, minimumLimitMegabytes), maximumLimitMegabytes)
    }
}

actor ResourceCacheAutoTrimCoordinator {
    static let shared = ResourceCacheAutoTrimCoordinator()

    private var scheduledTask: Task<Void, Never>?

    func scheduleIfNeeded() {
        guard ResourceCacheLimitSettings.isEnabled else { return }
        guard scheduledTask == nil else { return }
        scheduledTask = Task(priority: .utility) {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            await ResourceCacheCenter.enforceConfiguredLimit()
            await ResourceCacheAutoTrimCoordinator.shared.finishScheduledTask()
        }
    }

    func finishScheduledTask() {
        scheduledTask = nil
    }
}

nonisolated enum ResourceCacheAutoTrim {
    static func schedule() {
        guard ResourceCacheLimitSettings.isEnabled else { return }
        Task(priority: .utility) {
            await ResourceCacheAutoTrimCoordinator.shared.scheduleIfNeeded()
        }
    }
}

nonisolated enum RelatedPlaybackPrefetchPolicy {
    static func candidateLimit(
        environment: PlaybackEnvironment,
        backgroundPreloadLimit: Int,
        isPlaying: Bool,
        isBuffering: Bool
    ) -> Int {
        guard backgroundPreloadLimit >= 3,
              environment.networkClass == .wifi,
              !environment.isLowPowerModeEnabled,
              !environment.isThermallyConstrained,
              isPlaying,
              !isBuffering
        else {
            return 0
        }
        return min(2, max(1, backgroundPreloadLimit - 1))
    }
}

nonisolated enum ResourceCacheCenter {
    static func summary() async -> ResourceCacheSummary {
        await RemoteImageCache.shared.applyAdaptiveBudget()
        async let playURL = PlayURLCache.shared.statistics()
        async let image = RemoteImageCache.shared.statistics()
        async let apiMemory = BiliAPIResponseMemoryCache.shared.statistics()
        async let videoRangeMedia = VideoRangeCache.shared.statistics()
        async let progressiveMedia = ProgressiveMediaSegmentCache.shared.statistics()
        async let subtitlesAndDanmaku = SubtitleDanmakuResourceCache.shared.statistics()
        return await ResourceCacheSummary(
            playURL: playURL,
            image: image,
            api: BiliURLSessionFactory.apiCacheStatistics(),
            apiMemory: apiMemory,
            videoRangeMedia: videoRangeMedia,
            progressiveMedia: progressiveMedia,
            subtitlesAndDanmaku: subtitlesAndDanmaku
        )
    }

    @discardableResult
    static func enforceConfiguredLimit() async -> ResourceCacheSummary {
        guard let limitBytes = ResourceCacheLimitSettings.limitBytes else {
            return await summary()
        }

        var current = await summary()
        guard current.managedBytes > limitBytes else { return current }

        let videoRangeTarget = max(
            0,
            current.videoRangeMedia.estimatedBytes - (current.managedBytes - limitBytes)
        )
        if videoRangeTarget < current.videoRangeMedia.estimatedBytes {
            await VideoRangeCache.shared.trim(to: Int64(videoRangeTarget))
            current = await summary()
            guard current.managedBytes > limitBytes else { return current }
        }

        await clearProgressiveMedia()
        current = await summary()
        guard current.managedBytes > limitBytes else { return current }

        await clearImages(includeDisk: true)
        current = await summary()
        guard current.managedBytes > limitBytes else { return current }

        await clearAPI()
        current = await summary()
        guard current.managedBytes > limitBytes else { return current }

        await clearSubtitlesAndDanmaku()
        current = await summary()
        guard current.managedBytes > limitBytes else { return current }

        await clearPlayURL()
        return await summary()
    }

    static func clearPlayURL() async {
        await PlayURLCache.shared.clearMemoryCache()
        await VideoPreloadCenter.shared.clearPlayURLCache()
    }

    static func clearImages(includeDisk: Bool) async {
        await RemoteImageCache.shared.clearMemoryCache(cancelInFlight: true)
        if includeDisk {
            await RemoteImageCache.shared.clearDiskCache()
        }
    }

    static func clearAPI() async {
        BiliURLSessionFactory.clearAPICache()
        await BiliAPIResponseMemoryCache.shared.clear()
    }

    static func clearSubtitlesAndDanmaku() async {
        await SubtitleDanmakuResourceCache.shared.clear()
    }

    static func clearProgressiveMedia() async {
        await ProgressiveMediaSegmentCache.shared.clear()
        await VideoRangeCache.shared.clear()
    }

    static func clearAll() async {
        await clearPlayURL()
        await clearImages(includeDisk: true)
        await clearAPI()
        await clearProgressiveMedia()
        await clearSubtitlesAndDanmaku()
    }
}
