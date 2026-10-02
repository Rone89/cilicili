import Foundation
import XCTest
@testable import bili

final class VideoRangeCacheCancellationTests: XCTestCase {
    func testCancelledJoinedConsumerDoesNotCancelExternalOwner() async throws {
        let cache = makeCache()
        let url = try XCTUnwrap(URL(string: "https://fixture.invalid/\(UUID().uuidString).m4s"))
        let range = HTTPByteRange(start: 0, endInclusive: 15)
        let owner = await cache.reserveExternalFetch(url: url, range: range, maxCacheBytes: 100)
        guard case let .reserved(token) = owner else { return XCTFail("Missing owner") }
        let joined = await cache.reserveExternalFetch(url: url, range: range, maxCacheBytes: 100)
        guard case let .pending(lease) = joined else { return XCTFail("Missing join") }
        let cancelled = expectation(description: "Joined consumer exits before owner completes")
        let consumer = Task {
            do {
                _ = try await lease.value
                XCTFail("Cancelled consumer returned data")
            } catch {
                XCTAssertTrue(error is CancellationError)
            }
            cancelled.fulfill()
        }
        consumer.cancel()
        await fulfillment(of: [cancelled], timeout: 2)
        let next = await cache.reserveExternalFetch(url: url, range: range, maxCacheBytes: 100)
        guard case let .pending(nextLease) = next else { return XCTFail("Owner was cancelled") }
        let data = Data(repeating: 4, count: 16)
        await cache.finishExternalFetch(token, data: data)
        let received = try await nextLease.value
        XCTAssertEqual(received, data)
        await cache.clear()
    }

    func testLateExternalCompletionCannotOverwriteReplacementGeneration() async throws {
        let cache = makeCache()
        let url = try XCTUnwrap(URL(string: "https://fixture.invalid/\(UUID().uuidString).m4s"))
        let range = HTTPByteRange(start: 0, endInclusive: 15)
        let first = await cache.reserveExternalFetch(url: url, range: range, maxCacheBytes: 100)
        guard case let .reserved(old) = first else { return XCTFail("Missing old owner") }
        await cache.invalidate(urls: [url.absoluteString])
        let second = await cache.reserveExternalFetch(url: url, range: range, maxCacheBytes: 100)
        guard case let .reserved(new) = second else { return XCTFail("Missing new owner") }
        await cache.finishExternalFetch(old, data: Data(repeating: 1, count: 16))
        let next = await cache.reserveExternalFetch(url: url, range: range, maxCacheBytes: 100)
        guard case let .pending(lease) = next else { return XCTFail("Stale completion entered cache") }
        await cache.failExternalFetch(old, error: CancellationError())
        let expected = Data(repeating: 2, count: 16)
        await cache.finishExternalFetch(new, data: expected)
        let received = try await lease.value
        XCTAssertEqual(received, expected)
        await cache.clear()
    }

    private func makeCache() -> VideoRangeCache {
        VideoRangeCache(rootURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("RangeCancellation-\(UUID().uuidString)"))
    }
}
