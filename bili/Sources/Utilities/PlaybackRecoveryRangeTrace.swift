import CryptoKit
import Foundation
import QuartzCore

nonisolated final class RecoveryRangeScope: @unchecked Sendable {
#if DEBUG
    struct Identity: Hashable, Sendable {
        let resource: String
        let track: String
        let start: Int64
        let length: Int64
        let host: String
    }

    struct Ticket: Sendable {
        let traceID: String
        let requestID: String
        let identity: Identity
        let origin: String
        let target: Bool
        let sameWarmRange: String
    }

    private struct ActiveRequest {
        let ticket: Ticket
        var source: String
    }

    private struct PendingEvent {
        let traceID: String
        let name: String
        let at: Double
        let fields: [String: String]
    }

    private static let maximumActiveRequestCount = 256
    private static let maximumWarmedIdentityCount = 256
    private static let terminalEventNames: Set<String> = [
        "rangeComplete",
        "rangeFailed",
        "rangeCancelled",
        "rangeEnded",
    ]
    private static let sourceEventNames: Set<String> = [
        "rangeSource",
        "rangeFirstByte",
        "rangeComplete",
    ]

    private let lock = NSLock()
    private var attachedTraceID: String?
    private var attachedTargets: [Identity] = []
    private var activeRequests: [String: ActiveRequest] = [:]
    private var activeRequestOrder: [String] = []
    private var connectionRequestIDs: [ObjectIdentifier: String] = [:]
    private var connectionOrder: [ObjectIdentifier] = []
    private var warmedIdentities: [Identity] = []
    private var terminalRequestIDs: Set<String> = []
    private var terminalRequestOrder: [String] = []

    init() {}

    nonisolated static func identity(
        url: URL,
        track: String,
        range: HTTPByteRange
    ) -> Identity {
        Identity(
            resource: sha256Hex(url.absoluteString),
            track: track,
            start: range.start,
            length: range.length,
            host: sanitizedHost(url.host)
        )
    }

    nonisolated func attach(
        traceID: String,
        targets: [Identity],
        at: Double = CACurrentMediaTime()
    ) {
        let oldRequestCount: Int? = withLock {
            if attachedTraceID == traceID {
                attachedTargets = targets
                return nil
            }

            let oldRequestCount = activeRequests.values.reduce(into: 0) { count, request in
                if request.ticket.traceID != traceID {
                    count += 1
                }
            }
            attachedTraceID = traceID
            attachedTargets = targets
            warmedIdentities.removeAll(keepingCapacity: true)
            return oldRequestCount
        }

        guard let oldRequestCount, !traceID.isEmpty else { return }
        RecoveryTraceStore.shared.event(
            traceID,
            "previousSeekRangeStillActiveAtNewSeek",
            at: at,
            fields: [
                "oldRangeStillActive": oldRequestCount > 0 ? "true" : "false",
                "oldRequestCount": String(oldRequestCount),
            ]
        )
    }

    nonisolated func detach(traceID: String?) {
        withLock {
            guard attachedTraceID == traceID else { return }
            attachedTraceID = nil
            attachedTargets.removeAll(keepingCapacity: true)
            warmedIdentities.removeAll(keepingCapacity: true)
        }
    }

    nonisolated func begin(
        identity: Identity,
        origin: String,
        traceID: String? = nil,
        at: Double = CACurrentMediaTime()
    ) -> Ticket? {
        let result: (ticket: Ticket, fields: [String: String]?) = withLock {
            let selectedTraceID = traceID ?? attachedTraceID ?? ""
            let usesAttachedContext = traceID == nil || traceID == attachedTraceID
            let isTarget = usesAttachedContext && attachedTargets.contains { target in
                Self.matchesTarget(identity, target: target)
            }
            let sameWarmRange: String = {
                guard usesAttachedContext else { return "unknown" }
                if warmedIdentities.contains(identity) {
                    return "true"
                } else if warmedIdentities.contains(where: { $0.track == identity.track }) {
                    return "false"
                } else {
                    return "unknown"
                }
            }()

            let ticket = Ticket(
                traceID: selectedTraceID,
                requestID: UUID().uuidString,
                identity: identity,
                origin: origin,
                target: isTarget,
                sameWarmRange: sameWarmRange
            )

            activeRequests[ticket.requestID] = ActiveRequest(
                ticket: ticket,
                source: "unknown"
            )
            activeRequestOrder.append(ticket.requestID)
            trimActiveRequestsIfNeeded()

            if usesAttachedContext, traceID != nil, !selectedTraceID.isEmpty {
                rememberWarm(identity)
            }

            let fields = fields(for: ticket, source: "unknown", warmJoinConfirmed: "unknown")
            return (ticket, selectedTraceID.isEmpty ? nil : fields)
        }

        if let fields = result.fields {
            RecoveryTraceStore.shared.event(
                result.ticket.traceID,
                "rangeRequested",
                at: at,
                fields: fields
            )
        }
        return result.ticket
    }

    nonisolated func ticket(for requestID: String?) -> Ticket? {
        guard let requestID else { return nil }
        return withLock { activeRequests[requestID]?.ticket }
    }

    nonisolated func associateConnection(
        _ connectionID: ObjectIdentifier,
        requestID: String?
    ) {
        withLock {
            guard let requestID else {
                connectionRequestIDs[connectionID] = nil
                connectionOrder.removeAll { $0 == connectionID }
                return
            }

            if connectionRequestIDs[connectionID] == nil {
                connectionOrder.append(connectionID)
            }
            connectionRequestIDs[connectionID] = requestID
            while connectionOrder.count > Self.maximumActiveRequestCount {
                let expiredConnectionID = connectionOrder.removeFirst()
                connectionRequestIDs[expiredConnectionID] = nil
            }
        }
    }

    nonisolated func connectionClosed(_ connectionID: ObjectIdentifier) {
        let pendingEvent: PendingEvent? = withLock {
            guard let requestID = connectionRequestIDs.removeValue(forKey: connectionID) else {
                return nil
            }
            connectionOrder.removeAll { $0 == connectionID }
            guard let activeRequest = activeRequests[requestID],
                  !activeRequest.ticket.traceID.isEmpty
            else { return nil }

            return PendingEvent(
                traceID: activeRequest.ticket.traceID,
                name: "localConnectionClosed",
                at: CACurrentMediaTime(),
                fields: fields(for: activeRequest.ticket, source: "local")
            )
        }

        guard let pendingEvent else { return }
        RecoveryTraceStore.shared.event(
            pendingEvent.traceID,
            pendingEvent.name,
            at: pendingEvent.at,
            fields: pendingEvent.fields
        )
    }

    nonisolated func event(
        _ ticket: Ticket?,
        _ name: String,
        source: String? = nil,
        bytes: Int? = nil,
        host: String? = nil,
        at: Double = CACurrentMediaTime()
    ) {
        guard let ticket else { return }

        let pendingEvents: [PendingEvent] = withLock {
            let isTerminal = Self.terminalEventNames.contains(name)
            guard !isTerminal || !terminalRequestIDs.contains(ticket.requestID) else {
                return []
            }

            var effectiveSource = source
            if var activeRequest = activeRequests[ticket.requestID] {
                if effectiveSource == nil,
                   Self.sourceEventNames.contains(name) || isTerminal {
                    effectiveSource = activeRequest.source
                }
                if Self.sourceEventNames.contains(name), let source {
                    activeRequest.source = source
                    effectiveSource = source
                }

                activeRequests[ticket.requestID] = activeRequest
            } else if Self.sourceEventNames.contains(name) || isTerminal {
                effectiveSource = effectiveSource ?? "unknown"
            }

            if isTerminal {
                rememberTerminalRequest(ticket.requestID)
                activeRequests[ticket.requestID] = nil
                activeRequestOrder.removeAll { $0 == ticket.requestID }
                removeConnections(for: ticket.requestID)
            }

            var fields = fields(
                for: ticket,
                source: effectiveSource,
                warmJoinConfirmed: ticket.sameWarmRange == "true" ? "unknown" : nil
            )
            if let effectiveSource {
                fields["source"] = effectiveSource
            }
            if let bytes {
                fields["bytes"] = String(bytes)
            }
            if let host { fields["responseHost"] = Self.sanitizedHost(host) }
            var pendingEvents: [PendingEvent] = []
            if !ticket.traceID.isEmpty {
                pendingEvents.append(
                    PendingEvent(
                        traceID: ticket.traceID,
                        name: name,
                        at: at,
                        fields: fields
                    ))
            }

            if isTerminal,
               let currentTraceID = attachedTraceID,
               !currentTraceID.isEmpty,
               currentTraceID != ticket.traceID,
               ["rangeComplete", "rangeFailed", "rangeCancelled"].contains(name) {
                pendingEvents.append(
                    PendingEvent(
                        traceID: currentTraceID,
                        name: name == "rangeComplete" ? "oldRangeCompleted" : name == "rangeCancelled" ? "oldRangeCancelled" : "oldRangeFailed",
                        at: at,
                        fields: fields
                    ))
            }
            return pendingEvents
        }

        for pendingEvent in pendingEvents {
            RecoveryTraceStore.shared.event(
                pendingEvent.traceID,
                pendingEvent.name,
                at: pendingEvent.at,
                fields: pendingEvent.fields
            )
        }
    }

    nonisolated var activeRequestCount: Int {
        withLock { activeRequests.count }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private func trimActiveRequestsIfNeeded() {
        while activeRequestOrder.count > Self.maximumActiveRequestCount {
            let requestID = activeRequestOrder.removeFirst()
            activeRequests[requestID] = nil
            removeConnections(for: requestID)
        }
    }

    private func removeConnections(for requestID: String) {
        let connectionIDs = connectionRequestIDs.compactMap { connectionID, mappedRequestID in
            mappedRequestID == requestID ? connectionID : nil
        }
        for connectionID in connectionIDs {
            connectionRequestIDs[connectionID] = nil
            connectionOrder.removeAll { $0 == connectionID }
        }
    }

    private func rememberWarm(_ identity: Identity) {
        guard !warmedIdentities.contains(identity) else { return }
        warmedIdentities.append(identity)
        while warmedIdentities.count > Self.maximumWarmedIdentityCount {
            warmedIdentities.removeFirst()
        }
    }

    private func rememberTerminalRequest(_ requestID: String) {
        guard terminalRequestIDs.insert(requestID).inserted else { return }
        terminalRequestOrder.append(requestID)
        while terminalRequestOrder.count > Self.maximumActiveRequestCount {
            let expiredRequestID = terminalRequestOrder.removeFirst()
            terminalRequestIDs.remove(expiredRequestID)
        }
    }

    private static func matchesTarget(_ identity: Identity, target: Identity) -> Bool {
        guard identity.resource == target.resource,
              identity.track == target.track,
              target.start <= identity.start
        else { return false }

        let offset = identity.start - target.start
        guard offset >= 0,
              target.length >= offset,
              identity.length >= 0
        else { return false }

        return identity.length <= target.length - offset
    }

    private func fields(
        for ticket: Ticket,
        source: String? = nil,
        warmJoinConfirmed: String? = nil
    ) -> [String: String] {
        var fields = [
            "target": String(ticket.target),
            "resource": ticket.identity.resource,
            "start": String(ticket.identity.start),
            "length": String(ticket.identity.length),
            "requestedHost": ticket.identity.host,
            "track": ticket.identity.track,
            "requestID": ticket.requestID,
            "origin": ticket.origin,
            "warmAndPlayerSameRange": ticket.sameWarmRange,
        ]
        if ticket.sameWarmRange == "true" {
            fields["warmJoinConfirmed"] = warmJoinConfirmed ?? "unknown"
        }
        if let source {
            fields["source"] = source
        }
        return fields
    }

    private static func sha256Hex(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", Int($0)) }
            .joined()
    }

    private static func sanitizedHost(_ host: String?) -> String {
        var result = ""
        for scalar in (host ?? "").lowercased().unicodeScalars {
            switch scalar.value {
            case 45, 46, 48...57, 65...90, 97...122:
                result.unicodeScalars.append(scalar)
            default:
                continue
            }
        }
        return result.isEmpty ? "unknown" : result
    }
#endif
}
