import Foundation
import XCTest
@testable import bili

#if DEBUG
final class PlaybackRecoveryRangeTaskOwnershipTests: XCTestCase {
    func testWarmReservationExactJoinSharesOwnerTaskAndCompletes() async throws {
        let url = try uniqueURL()
        let range = makeRange(start: 0, length: 128)
        let identity = RecoveryRangeScope.identity(url: url, track: "video", range: range)
        let (scope, traceID) = makeTrace()
        let warm = try XCTUnwrap(scope.begin(identity: identity, origin: "warm", traceID: traceID, at: 1))
        let player = try XCTUnwrap(scope.begin(identity: identity, origin: "player", at: 2))

        let ownerReservation = await reserve(url: url, range: range, ticket: warm)
        guard case let .reserved(ownerToken) = ownerReservation else {
            XCTFail("warm reservation was not reserved")
            return
        }
        let joinedReservation = await reserve(url: url, range: range, ticket: player)
        guard case let .pending(joinedTask) = joinedReservation else {
            XCTFail("player reservation did not join")
            return
        }

        let created = try XCTUnwrap(eventFields(traceID, "rangeTaskCreated", requestID: warm.requestID))
        let joined = try XCTUnwrap(eventFields(traceID, "rangeTaskJoined", requestID: player.requestID))
        let taskID = try XCTUnwrap(created["taskID"])
        XCTAssertNotEqual(taskID, "-")
        XCTAssertEqual(joined["taskID"], taskID)
        XCTAssertEqual(joined["ownerTraceID"], traceID)
        XCTAssertEqual(joined["ownerRequestID"], warm.requestID)
        XCTAssertEqual(joined["ownerOrigin"], "warm")
        XCTAssertEqual(joined["joinKind"], "exact")
        XCTAssertEqual(joined["warmJoinConfirmed"], "true")
        XCTAssertEqual(joined["candidateHost"], url.host)

        let data = Data(repeating: 7, count: Int(range.length))
        await finish(ownerToken, ticket: warm, data: data)
        let joinedData = try await joinedTask.value
        XCTAssertEqual(joinedData, data)
        let completed = try XCTUnwrap(eventFields(traceID, "rangeTaskCompleted", requestID: warm.requestID))
        XCTAssertEqual(completed["taskID"], taskID)
        XCTAssertEqual(completed["ownerOrigin"], "warm")
    }

    func testContainingJoinKeepsOwnerTaskAndRecordsBothRanges() async throws {
        let url = try uniqueURL()
        let ownerRange = makeRange(start: 0, length: 128)
        let playerRange = makeRange(start: 32, length: 24)
        let (scope, traceID) = makeTrace()
        let warm = try XCTUnwrap(scope.begin(
            identity: RecoveryRangeScope.identity(url: url, track: "video", range: ownerRange),
            origin: "warm", traceID: traceID, at: 1
        ))
        let player = try XCTUnwrap(scope.begin(
            identity: RecoveryRangeScope.identity(url: url, track: "video", range: playerRange),
            origin: "player", at: 2
        ))

        let ownerReservation = await reserve(url: url, range: ownerRange, ticket: warm)
        guard case let .reserved(ownerToken) = ownerReservation else {
            XCTFail("warm reservation was not reserved")
            return
        }
        let joinedReservation = await reserve(url: url, range: playerRange, ticket: player)
        guard case let .pending(joinedTask) = joinedReservation else {
            XCTFail("subrange reservation did not join")
            return
        }
        let created = try XCTUnwrap(eventFields(traceID, "rangeTaskCreated", requestID: warm.requestID))
        let joined = try XCTUnwrap(eventFields(traceID, "rangeTaskJoined", requestID: player.requestID))
        XCTAssertEqual(joined["taskID"], created["taskID"])
        XCTAssertEqual(joined["joinKind"], "containing")
        XCTAssertEqual(joined["candidateRangeStart"], "32")
        XCTAssertEqual(joined["candidateRangeLength"], "24")
        XCTAssertEqual(joined["ownerRangeStart"], "0")
        XCTAssertEqual(joined["ownerRangeLength"], "128")

        await fail(ownerToken, ticket: warm)
        do {
            _ = try await joinedTask.value
            XCTFail("joined subrange unexpectedly completed")
        } catch {}
    }

    func testDifferentURLsWithSameRangeCreateDifferentTasks() async throws {
        let firstURL = try uniqueURL()
        let secondURL = try uniqueURL()
        let range = makeRange(start: 0, length: 64)
        let (scope, traceID) = makeTrace()
        let firstTicket = try XCTUnwrap(scope.begin(
            identity: RecoveryRangeScope.identity(url: firstURL, track: "video", range: range),
            origin: "warm", traceID: traceID, at: 1
        ))
        let secondTicket = try XCTUnwrap(scope.begin(
            identity: RecoveryRangeScope.identity(url: secondURL, track: "video", range: range),
            origin: "player", at: 2
        ))

        let first = await reserve(url: firstURL, range: range, ticket: firstTicket)
        let second = await reserve(url: secondURL, range: range, ticket: secondTicket)
        guard case let .reserved(firstToken) = first,
              case let .reserved(secondToken) = second
        else {
            XCTFail("different candidates unexpectedly joined")
            return
        }

        let created = eventFieldSets(traceID, "rangeTaskCreated")
        XCTAssertEqual(created.count, 2)
        let firstID = created.first { $0["candidateHost"] == firstURL.host }?["taskID"]
        let secondID = created.first { $0["candidateHost"] == secondURL.host }?["taskID"]
        XCTAssertNotNil(firstID)
        XCTAssertNotNil(secondID)
        XCTAssertNotEqual(firstID, secondID)
        XCTAssertTrue(eventFieldSets(traceID, "rangeTaskJoined").isEmpty)

        await fail(firstToken, ticket: firstTicket)
        await fail(secondToken, ticket: secondTicket)
    }

    func testCacheHitHasNoTaskOwnershipID() async throws {
        let url = try uniqueURL()
        let range = makeRange(start: 0, length: 48)
        let identity = RecoveryRangeScope.identity(url: url, track: "video", range: range)
        let (scope, traceID) = makeTrace()
        let warm = try XCTUnwrap(scope.begin(identity: identity, origin: "warm", traceID: traceID, at: 1))
        let ownerReservation = await reserve(url: url, range: range, ticket: warm)
        guard case let .reserved(ownerToken) = ownerReservation else {
            XCTFail("warm reservation was not reserved")
            return
        }
        await finish(ownerToken, ticket: warm, data: Data(repeating: 3, count: Int(range.length)))

        let player = try XCTUnwrap(scope.begin(identity: identity, origin: "player", at: 2))
        let cacheResult = await reserve(url: url, range: range, ticket: player)
        guard case let .cached(data) = cacheResult else {
            XCTFail("completed reservation was not a cache hit")
            return
        }
        XCTAssertEqual(data.count, Int(range.length))
        let hit = try XCTUnwrap(eventFields(traceID, "rangeTaskCacheHit", requestID: player.requestID))
        XCTAssertEqual(hit["taskID"], "-")
        XCTAssertEqual(hit["ownerTraceID"], "-")
        XCTAssertEqual(hit["ownerRequestID"], "-")
        XCTAssertEqual(hit["ownerOrigin"], "unknown")
        XCTAssertTrue(eventFieldSets(traceID, "rangeTaskCreated").count == 1)
    }

    func testFailedReservationClearsMetadataBeforeNewReservation() async throws {
        let url = try uniqueURL()
        let range = makeRange(start: 0, length: 40)
        let identity = RecoveryRangeScope.identity(url: url, track: "video", range: range)
        let (scope, traceID) = makeTrace()
        let warm = try XCTUnwrap(scope.begin(identity: identity, origin: "warm", traceID: traceID, at: 1))

        let first = await reserve(url: url, range: range, ticket: warm)
        guard case let .reserved(firstToken) = first else {
            XCTFail("first reservation was not reserved")
            return
        }
        await fail(firstToken, ticket: warm)

        let second = await reserve(url: url, range: range, ticket: warm)
        guard case let .reserved(secondToken) = second else {
            XCTFail("metadata was not cleared after failure")
            return
        }
        let created = eventFieldSets(traceID, "rangeTaskCreated")
        XCTAssertEqual(created.count, 2)
        XCTAssertNotEqual(created[0]["taskID"], created[1]["taskID"])
        await fail(secondToken, ticket: warm)
    }

    private func makeTrace() -> (RecoveryRangeScope, String) {
        let scope = RecoveryRangeScope()
        let traceID = RecoveryTraceStore.shared.start(type: "userSeek", metricsID: nil, at: 0)
        scope.attach(traceID: traceID, targets: [], at: 0.5)
        return (scope, traceID)
    }

    private func reserve(
        url: URL,
        range: HTTPByteRange,
        ticket: RecoveryRangeScope.Ticket
    ) async -> VideoRangeExternalFetchReservation {
        await RecoveryRangeTaskContext.$current.withValue(.init(ticket: ticket)) {
            await VideoRangeCache.shared.reserveExternalFetch(
                url: url,
                range: range,
                maxCacheBytes: 1_000_000
            )
        }
    }

    private func finish(
        _ token: VideoRangeExternalFetchToken,
        ticket: RecoveryRangeScope.Ticket,
        data: Data
    ) async {
        await RecoveryRangeTaskContext.$current.withValue(.init(ticket: ticket)) {
            await VideoRangeCache.shared.finishExternalFetch(token, data: data)
        }
    }

    private func fail(_ token: VideoRangeExternalFetchToken, ticket: RecoveryRangeScope.Ticket) async {
        await RecoveryRangeTaskContext.$current.withValue(.init(ticket: ticket)) {
            await VideoRangeCache.shared.failExternalFetch(token, error: CancellationError())
        }
    }

    private func eventFields(
        _ traceID: String,
        _ name: String,
        requestID: String? = nil
    ) -> [String: String]? {
        eventFieldSets(traceID, name).first { requestID == nil || $0["requestID"] == requestID }
    }

    private func eventFieldSets(_ traceID: String, _ name: String) -> [[String: String]] {
        let prefix = "[RecoveryTrace] id=\(traceID) "
        let marker = " event=\(name) fields="
        return RecoveryTraceStore.shared.exportText()
            .split(whereSeparator: \.isNewline)
            .compactMap { rawLine in
                let line = String(rawLine)
                guard line.hasPrefix(prefix), line.contains(marker),
                      let fieldsStart = line.range(of: " fields=")
                else { return nil }
                return line[fieldsStart.upperBound...]
                    .split(separator: ",")
                    .reduce(into: [String: String]()) { fields, pair in
                        let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                        if parts.count == 2 { fields[parts[0]] = parts[1] }
                    }
            }
    }

    private func uniqueURL() throws -> URL {
        try XCTUnwrap(URL(string: "https://range-owner-\(UUID().uuidString.lowercased()).example.invalid/segment.m4s"))
    }

    private func makeRange(start: Int64, length: Int64) -> HTTPByteRange {
        HTTPByteRange(start: start, endInclusive: start + length - 1)
    }
}
#endif
