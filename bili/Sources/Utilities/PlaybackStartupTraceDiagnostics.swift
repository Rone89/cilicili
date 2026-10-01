import Foundation

nonisolated enum RelatedPrefetchClickState: String, CaseIterable, Sendable {
    case notScheduled
    case scheduled
    case running
    case completed
    case completedUncached
    case failed
    case cancelled
    case expired
    case evicted
    case unknown
}

nonisolated enum RelatedPrefetchConsumeResult: String, CaseIterable, Sendable {
    case completedCacheHit
    case pendingJoin
    case missNoPrefetch
    case missExpired
    case missEvicted
    case missDifferentIdentity
    case missDifferentQuality
    case missDifferentCodec
    case prefetchFailed
    case completedUncached
    case unknownMiss
}

nonisolated enum RelatedPrefetchDiagnostics {
    struct StageEvent: Equatable, Sendable {
        let name: String
        let fields: [String: String]
    }

    static func stageEvent(from message: String) -> StageEvent {
        let tokens = message.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = tokens.first else {
            return StageEvent(name: "manifestStage", fields: [:])
        }
        let firstSeparator = first.firstIndex(of: "=")
        let name = firstSeparator.map { String(first[..<$0]) } ?? first
        var fields: [String: String] = [:]
        if let firstSeparator {
            fields["value"] = String(first[first.index(after: firstSeparator)...])
        }
        var details: [String] = []
        for token in tokens.dropFirst() {
            guard let separator = token.firstIndex(of: "="), separator != token.startIndex else {
                details.append(token)
                continue
            }
            let key = String(token[..<separator])
            let value = String(token[token.index(after: separator)...])
            fields[key] = value
        }
        if !details.isEmpty {
            fields["details"] = details.joined(separator: " ")
        }
        return StageEvent(name: name, fields: fields)
    }

    static func stateAtClick(
        storedState: String?,
        scheduledAt: CFTimeInterval?,
        startedAt: CFTimeInterval?,
        completedAt: CFTimeInterval?,
        clickAt: CFTimeInterval,
        cacheExpiresAt: CFTimeInterval? = nil
    ) -> RelatedPrefetchClickState {
        guard let storedState else { return .notScheduled }
        if let scheduledAt, clickAt < scheduledAt { return .notScheduled }
        if let startedAt, clickAt < startedAt { return .scheduled }
        if let completedAt, completedAt <= clickAt {
            switch storedState {
            case "failed": return .failed
            case "cancelled": return .cancelled
            case "evicted": return .evicted
            case "completedUncached": return .completedUncached
            case "expired": return .expired
            default:
                if let cacheExpiresAt, clickAt >= cacheExpiresAt {
                    return .expired
                }
                return .completed
            }
        }
        if startedAt != nil { return .running }
        return .scheduled
    }

    static func leadMilliseconds(startedAt: CFTimeInterval?, clickAt: CFTimeInterval) -> Double? {
        guard let startedAt, clickAt >= startedAt else { return nil }
        return (clickAt - startedAt) * 1_000
    }

    static func leadBucket(for milliseconds: Double?) -> String {
        guard let milliseconds else { return "unknown" }
        switch milliseconds {
        case ..<200: return "lt200ms"
        case ..<500: return "200-500ms"
        case ..<1_000: return "500-1000ms"
        case ..<2_000: return "1-2s"
        default: return "gt2s"
        }
    }

    static func consumeResult(
        cacheSource: String?,
        stateAtClick: RelatedPrefetchClickState,
        missReason: String?
    ) -> RelatedPrefetchConsumeResult {
        switch cacheSource {
        case "pendingCache", "joined": return .pendingJoin
        case "cache", "playableCache", "storedCache", "completedCache": return .completedCacheHit
        default: break
        }
        switch missReason {
        case "prefetchMissDifferentCID", "prefetchMissDifferentIdentity": return .missDifferentIdentity
        case "prefetchMissDifferentQuality": return .missDifferentQuality
        case "prefetchMissDifferentCodec": return .missDifferentCodec
        case "prefetchExpired": return .missExpired
        case "cacheMissingBeforeExpiry": return .missEvicted
        case "prefetchDidNotProduceCache": return .prefetchFailed
        case "playURLNotReusable": return .completedUncached
        case "prefetchNotStarted": return .missNoPrefetch
        default:
            return stateAtClick == .notScheduled ? .missNoPrefetch : .unknownMiss
        }
    }

    static func qualityCodecMatch(
        requestedQuality: Int?, prefetchQuality: Int?, requestedCodec: String?, prefetchCodec: String?
    ) -> (quality: Bool?, codec: Bool?) {
        let quality = requestedQuality.flatMap { requested in prefetchQuality.map { requested == $0 } }
        let codec = requestedCodec.flatMap { requested in prefetchCodec.map { requested == $0 } }
        return (quality, codec)
    }

    static func cdnHostLabel(_ host: String?) -> String {
        guard let host, !host.isEmpty else { return "unknown" }
        let firstLabel = host.lowercased().split(separator: ".").first.map(String.init) ?? "unknown"
        let safeLabel = firstLabel.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return safeLabel.isEmpty ? "unknown" : String(safeLabel.prefix(32))
    }
}
