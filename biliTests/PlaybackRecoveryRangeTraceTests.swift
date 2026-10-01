import Foundation
import XCTest
@testable import bili

#if DEBUG
final class PlaybackRecoveryRangeTraceTests: XCTestCase {
    func testIdentityUsesOpaqueResourceDigestAndSanitizedHost() throws {
        let url = try XCTUnwrap(
            URL(string: "https://CDN.Example.com:443/video/segment.m4s?token=secret")
        )
        let identity = RecoveryRangeScope.identity(
            url: url,
            track: "video",
            range: HTTPByteRange(start: 10, endInclusive: 19)
        )

        XCTAssertEqual(identity.length, 10)
        XCTAssertEqual(identity.host, "cdn.example.com")
        XCTAssertEqual(identity.resource.count, 64)
        XCTAssertNotEqual(identity.resource, url.absoluteString)
        XCTAssertFalse(identity.resource.contains("secret"))
    }

    func testWarmRangeClassificationTracksSameDifferentAndUnknownRanges() throws {
        let scope = RecoveryRangeScope()
        let first = try XCTUnwrap(URL(string: "https://cdn.example.com/video.m4s"))
        let warmRange = RecoveryRangeScope.identity(
            url: first,
            track: "video",
            range: HTTPByteRange(start: 0, endInclusive: 99)
        )
        let otherRange = RecoveryRangeScope.identity(
            url: first,
            track: "video",
            range: HTTPByteRange(start: 100, endInclusive: 199)
        )

        let traceID = RecoveryTraceStore.shared.start(type: "manualResume", metricsID: nil, at: 0)
        scope.attach(traceID: traceID, targets: [], at: 1)

        let firstWarm = try XCTUnwrap(
            scope.begin(identity: warmRange, origin: "warm", traceID: traceID, at: 2)
        )
        XCTAssertEqual(firstWarm.sameWarmRange, "unknown")

        let samePlayer = try XCTUnwrap(
            scope.begin(identity: warmRange, origin: "player", at: 3)
        )
        XCTAssertEqual(samePlayer.sameWarmRange, "true")

        let differentPlayer = try XCTUnwrap(
            scope.begin(identity: otherRange, origin: "player", at: 4)
        )
        XCTAssertEqual(differentPlayer.sameWarmRange, "false")
    }

    func testTargetMatchesContainedRangeButRejectsDifferentResourceAndManualResume() throws {
        let scope = RecoveryRangeScope()
        let targetURL = try XCTUnwrap(URL(string: "https://cdn.example.com/video.m4s"))
        let otherURL = try XCTUnwrap(URL(string: "https://other.example.com/video.m4s"))
        let target = RecoveryRangeScope.identity(
            url: targetURL,
            track: "video",
            range: HTTPByteRange(start: 0, endInclusive: 99)
        )
        let contained = RecoveryRangeScope.identity(
            url: targetURL,
            track: "video",
            range: HTTPByteRange(start: 20, endInclusive: 39)
        )
        let differentResource = RecoveryRangeScope.identity(
            url: otherURL,
            track: "video",
            range: HTTPByteRange(start: 20, endInclusive: 39)
        )
        let traceID = RecoveryTraceStore.shared.start(type: "userSeek", metricsID: nil, at: 0)

        scope.attach(traceID: traceID, targets: [target], at: 1)
        let containedTicket = try XCTUnwrap(scope.begin(identity: contained, origin: "player", at: 2))
        let mismatchedTicket = try XCTUnwrap(
            scope.begin(identity: differentResource, origin: "player", at: 3)
        )
        XCTAssertTrue(containedTicket.target)
        XCTAssertFalse(mismatchedTicket.target)

        scope.attach(traceID: traceID, targets: [], at: 4)
        let manualResumeTicket = try XCTUnwrap(
            scope.begin(identity: contained, origin: "manualResume", at: 5)
        )
        XCTAssertFalse(manualResumeTicket.target)
    }

    func testTerminalEventsAreDeduplicatedAndCarrySourceToFirstByteAndComplete() throws {
        let scope = RecoveryRangeScope()
        let url = try XCTUnwrap(URL(string: "https://cdn.example.com/video.m4s"))
        let identity = RecoveryRangeScope.identity(
            url: url,
            track: "video",
            range: HTTPByteRange(start: 0, endInclusive: 99)
        )
        let traceID = RecoveryTraceStore.shared.start(type: "userSeek", metricsID: nil, at: 0)
        scope.attach(traceID: traceID, targets: [identity], at: 1)
        let ticket = try XCTUnwrap(scope.begin(identity: identity, origin: "player", at: 2))

        scope.event(ticket, "rangeSource", source: "network", at: 2.5)
        scope.event(ticket, "rangeFirstByte", bytes: 12, at: 3)
        scope.event(ticket, "rangeComplete", bytes: 100, at: 4)
        scope.event(ticket, "rangeComplete", source: "cache", bytes: 100, at: 5)
        scope.event(ticket, "rangeFailed", source: "network", at: 6)

        XCTAssertEqual(scope.activeRequestCount, 0)
        let summary = try XCTUnwrap(RecoveryTraceStore.shared.summary(traceID))
        XCTAssertTrue(summary.contains("targetVideoRangeSource=network"))
        XCTAssertEqual(
            eventNames(in: summary),
            [
                "seekRequested",
                "previousSeekRangeStillActiveAtNewSeek",
                "rangeRequested",
                "rangeSource",
                "rangeFirstByte",
                "rangeComplete",
            ]
        )
        XCTAssertFalse(summary.contains("rangeComplete,rangeComplete"))
    }

    func testAttachingNewTraceRetainsOldTicketTraceAndDetachDoesNotCancelRequest() throws {
        let scope = RecoveryRangeScope()
        let url = try XCTUnwrap(URL(string: "https://cdn.example.com/video.m4s"))
        let oldIdentity = RecoveryRangeScope.identity(
            url: url,
            track: "video",
            range: HTTPByteRange(start: 0, endInclusive: 99)
        )
        let newIdentity = RecoveryRangeScope.identity(
            url: url,
            track: "video",
            range: HTTPByteRange(start: 100, endInclusive: 199)
        )
        let oldTraceID = RecoveryTraceStore.shared.start(type: "userSeek", metricsID: nil, at: 0)
        let newTraceID = RecoveryTraceStore.shared.start(type: "userSeek", metricsID: nil, at: 0)

        scope.attach(traceID: oldTraceID, targets: [], at: 1)
        let oldTicket = try XCTUnwrap(scope.begin(identity: oldIdentity, origin: "player", at: 2))
        scope.attach(traceID: newTraceID, targets: [], at: 3)
        XCTAssertEqual(scope.activeRequestCount, 1)
        XCTAssertEqual(oldTicket.traceID, oldTraceID)

        let newTicket = try XCTUnwrap(scope.begin(identity: newIdentity, origin: "player", at: 4))
        XCTAssertEqual(newTicket.traceID, newTraceID)
        XCTAssertEqual(scope.activeRequestCount, 2)

        scope.detach(traceID: newTraceID)
        XCTAssertEqual(scope.activeRequestCount, 2)
        scope.event(oldTicket, "rangeComplete", source: "network", at: 5)
        XCTAssertEqual(scope.activeRequestCount, 1)
        scope.event(newTicket, "rangeCancelled", at: 6)
        XCTAssertEqual(scope.activeRequestCount, 0)

        let oldSummary = try XCTUnwrap(RecoveryTraceStore.shared.summary(oldTraceID))
        XCTAssertEqual(
            eventNames(in: oldSummary),
            ["seekRequested", "previousSeekRangeStillActiveAtNewSeek", "rangeRequested", "rangeComplete"]
        )
        XCTAssertFalse(oldSummary.contains("oldRangeCompleted"))
        let newSummary = try XCTUnwrap(RecoveryTraceStore.shared.summary(newTraceID))
        XCTAssertTrue(newSummary.contains("oldRangeStillActive=true"))
        XCTAssertEqual(
            eventNames(in: newSummary),
            ["seekRequested", "previousSeekRangeStillActiveAtNewSeek", "rangeRequested", "rangeCancelled"]
        )
        XCTAssertFalse(newSummary.contains("oldRangeCompleted"))
    }

    func testUntracedRequestIsRetainedAcrossAttachAndCompletesInNewTrace() throws {
        let scope = RecoveryRangeScope()
        let url = try XCTUnwrap(URL(string: "https://cdn.example.com/video.m4s"))
        let identity = RecoveryRangeScope.identity(
            url: url,
            track: "video",
            range: HTTPByteRange(start: 0, endInclusive: 99)
        )

        let untracedTicket = try XCTUnwrap(
            scope.begin(identity: identity, origin: "player", at: 1)
        )
        XCTAssertEqual(untracedTicket.traceID, "")
        XCTAssertEqual(scope.activeRequestCount, 1)
        XCTAssertEqual(scope.ticket(for: untracedTicket.requestID)?.requestID, untracedTicket.requestID)
        XCTAssertNil(scope.ticket(for: nil))

        let traceID = RecoveryTraceStore.shared.start(type: "userSeek", metricsID: nil, at: 2)
        scope.attach(traceID: traceID, targets: [], at: 3)
        XCTAssertEqual(scope.activeRequestCount, 1)
        scope.event(untracedTicket, "rangeComplete", at: 4)
        XCTAssertEqual(scope.activeRequestCount, 0)
        XCTAssertNil(scope.ticket(for: untracedTicket.requestID))

        let summary = try XCTUnwrap(RecoveryTraceStore.shared.summary(traceID))
        XCTAssertTrue(summary.contains("oldRangeStillActive=true"))
        XCTAssertEqual(
            eventNames(in: summary),
            ["seekRequested", "previousSeekRangeStillActiveAtNewSeek", "oldRangeCompleted"]
        )
    }

    func testSameTraceAttachUpdatesTargetsWithoutResettingWarmIdentityOrDuplicatingOldEvent() throws {
        let scope = RecoveryRangeScope()
        let url = try XCTUnwrap(URL(string: "https://cdn.example.com/video.m4s"))
        let identity = RecoveryRangeScope.identity(
            url: url,
            track: "video",
            range: HTTPByteRange(start: 0, endInclusive: 99)
        )
        let traceID = RecoveryTraceStore.shared.start(type: "userSeek", metricsID: nil, at: 0)

        scope.attach(traceID: traceID, targets: [], at: 1)
        _ = try XCTUnwrap(scope.begin(identity: identity, origin: "warm", traceID: traceID, at: 2))
        scope.attach(traceID: traceID, targets: [identity], at: 3)
        let playerTicket = try XCTUnwrap(scope.begin(identity: identity, origin: "player", at: 4))

        XCTAssertTrue(playerTicket.target)
        XCTAssertEqual(playerTicket.sameWarmRange, "true")
        let summary = try XCTUnwrap(RecoveryTraceStore.shared.summary(traceID))
        XCTAssertEqual(
            summary.components(separatedBy: "previousSeekRangeStillActiveAtNewSeek").count - 1,
            1
        )
    }

    func testRangeEndedRemovesActiveRequestWithoutReportingCompletion() throws {
        let scope = RecoveryRangeScope()
        let url = try XCTUnwrap(URL(string: "https://cdn.example.com/video.m4s"))
        let identity = RecoveryRangeScope.identity(
            url: url,
            track: "video",
            range: HTTPByteRange(start: 0, endInclusive: 99)
        )
        let traceID = RecoveryTraceStore.shared.start(type: "userSeek", metricsID: nil, at: 0)
        scope.attach(traceID: traceID, targets: [], at: 1)
        let ticket = try XCTUnwrap(scope.begin(identity: identity, origin: "player", at: 2))

        scope.event(ticket, "rangeEnded", at: 3)
        scope.event(ticket, "rangeComplete", at: 4)

        let failedIdentity = RecoveryRangeScope.identity(
            url: url,
            track: "video",
            range: HTTPByteRange(start: 100, endInclusive: 199)
        )
        let failedTicket = try XCTUnwrap(scope.begin(identity: failedIdentity, origin: "player", at: 5))
        scope.event(failedTicket, "rangeFailed", source: "unknown", at: 6)
        scope.event(failedTicket, "rangeEnded", at: 7)

        XCTAssertEqual(scope.activeRequestCount, 0)
        XCTAssertNil(scope.ticket(for: ticket.requestID))
        let summary = try XCTUnwrap(RecoveryTraceStore.shared.summary(traceID))
        XCTAssertEqual(
            eventNames(in: summary),
            ["seekRequested", "previousSeekRangeStillActiveAtNewSeek", "rangeRequested", "rangeEnded", "rangeRequested", "rangeFailed"]
        )
        XCTAssertFalse(summary.contains("rangeEnded,rangeComplete"))
        XCTAssertFalse(summary.contains("rangeFailed,rangeEnded"))
    }

    func testConnectionClosedReportsLocalClosureAndLeavesUpstreamRequestActive() throws {
        let scope = RecoveryRangeScope()
        let url = try XCTUnwrap(URL(string: "https://cdn.example.com/video.m4s"))
        let identity = RecoveryRangeScope.identity(
            url: url,
            track: "video",
            range: HTTPByteRange(start: 0, endInclusive: 99)
        )
        let traceID = RecoveryTraceStore.shared.start(type: "userSeek", metricsID: nil, at: 0)
        scope.attach(traceID: traceID, targets: [], at: 1)
        let ticket = try XCTUnwrap(scope.begin(identity: identity, origin: "player", at: 2))
        let connection = NSObject()
        let connectionID = ObjectIdentifier(connection)

        scope.associateConnection(connectionID, requestID: ticket.requestID)
        scope.connectionClosed(connectionID)

        XCTAssertEqual(scope.activeRequestCount, 1)
        let summary = try XCTUnwrap(RecoveryTraceStore.shared.summary(traceID))
        XCTAssertTrue(summary.contains("localConnectionClosed"))

        scope.event(ticket, "rangeFailed", at: 3)
        XCTAssertEqual(scope.activeRequestCount, 0)
    }

    private func eventNames(in summary: String) -> [String] {
        guard let token = summary.split(separator: " ").first(where: { $0.hasPrefix("events=") }) else {
            return []
        }
        return token.dropFirst("events=".count).split(separator: ",").map { event in
            String(event.split(separator: "@", maxSplits: 1).first ?? event)
        }
    }
}
#endif
