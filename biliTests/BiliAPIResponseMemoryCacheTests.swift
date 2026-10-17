import Foundation
import XCTest

@testable import bili

final class BiliAPIResponseMemoryCacheTests: XCTestCase {
    func testFreshMissPreservesStaleFallbackAndAccounting() async {
        let cache = BiliAPIResponseMemoryCache()
        let start = Date(timeIntervalSince1970: 1_000)
        let payload = Data("cached profile".utf8)
        await cache.store(
            payload, for: "profile",
            policy: BiliAPIResponseCachePolicy(freshTTL: 30, staleTTL: 300),
            now: start
        )

        // This is the transport's actual lookup order: fresh, then stale.
        let fresh = await cache.freshData(for: "profile", now: start.addingTimeInterval(31))
        let stale = await cache.staleData(for: "profile", now: start.addingTimeInterval(31))
        let statistics = await cache.statistics(now: start.addingTimeInterval(31))

        XCTAssertNil(fresh)
        XCTAssertEqual(stale, payload)
        XCTAssertEqual(statistics.count, 1)
        XCTAssertEqual(statistics.estimatedBytes, payload.count)
        XCTAssertEqual(statistics.freshCount, 0)
        XCTAssertEqual(statistics.staleCount, 1)
        XCTAssertEqual(statistics.staleHits, 1)
        XCTAssertEqual(statistics.misses, 1)
        XCTAssertEqual(statistics.evictions, 0)
    }

    func testDataIsEvictedOnlyAfterFinalExpiration() async {
        let cache = BiliAPIResponseMemoryCache()
        let start = Date(timeIntervalSince1970: 1_000)
        let payload = Data("cached profile".utf8)
        await cache.store(
            payload, for: "profile",
            policy: BiliAPIResponseCachePolicy(freshTTL: 30, staleTTL: 300),
            now: start
        )

        let boundary = await cache.staleData(
            for: "profile", now: start.addingTimeInterval(300)
        )
        let expiredFresh = await cache.freshData(
            for: "profile", now: start.addingTimeInterval(301)
        )
        let expiredStale = await cache.staleData(
            for: "profile", now: start.addingTimeInterval(301)
        )
        let statistics = await cache.statistics(now: start.addingTimeInterval(301))

        XCTAssertEqual(boundary, payload)
        XCTAssertNil(expiredFresh)
        XCTAssertNil(expiredStale)
        XCTAssertEqual(statistics.count, 0)
        XCTAssertEqual(statistics.estimatedBytes, 0)
        XCTAssertEqual(statistics.evictions, 1)
    }

    func testFreshBoundaryAndReplacementUseTheNewLifetime() async {
        let cache = BiliAPIResponseMemoryCache()
        let start = Date(timeIntervalSince1970: 1_000)
        let policy = BiliAPIResponseCachePolicy(freshTTL: 30, staleTTL: 300)
        await cache.store(Data("old".utf8), for: "profile", policy: policy, now: start)
        let boundary = await cache.freshData(
            for: "profile", now: start.addingTimeInterval(30)
        )
        XCTAssertEqual(boundary, Data("old".utf8))

        let replacement = Data("new profile".utf8)
        await cache.store(
            replacement, for: "profile", policy: policy,
            now: start.addingTimeInterval(31)
        )
        let fresh = await cache.freshData(
            for: "profile", now: start.addingTimeInterval(60)
        )
        let statistics = await cache.statistics(now: start.addingTimeInterval(60))
        XCTAssertEqual(fresh, replacement)
        XCTAssertEqual(statistics.estimatedBytes, replacement.count)
        XCTAssertEqual(statistics.count, 1)
        XCTAssertEqual(statistics.freshCount, 1)
    }

    func testStatisticsDoesNotTrimStillReusableStaleData() async {
        let cache = BiliAPIResponseMemoryCache()
        let start = Date(timeIntervalSince1970: 1_000)
        let payload = Data("cached profile".utf8)
        await cache.store(
            payload, for: "profile",
            policy: BiliAPIResponseCachePolicy(freshTTL: 30, staleTTL: 300),
            now: start
        )
        let statistics = await cache.statistics(now: start.addingTimeInterval(31))
        let stale = await cache.staleData(for: "profile", now: start.addingTimeInterval(31))
        XCTAssertEqual(statistics.staleCount, 1)
        XCTAssertEqual(statistics.evictions, 0)
        XCTAssertEqual(stale, payload)
    }
}

