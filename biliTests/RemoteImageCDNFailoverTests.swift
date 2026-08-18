import XCTest
import UIKit
@testable import bili

final class RemoteImageCDNFailoverTests: XCTestCase {
    func testEligibleImageURLAddsInterchangeableCDNHosts() throws {
        let memory = RemoteImageCDNHealthMemory()
        let url = try XCTUnwrap(URL(string: "https://i0.hdslb.com/bfs/archive/example.jpg?imageView2/1/w/640"))

        let candidates = memory.orderedCandidates(for: [url])

        XCTAssertEqual(candidates.compactMap(\.host), ["i0.hdslb.com", "i1.hdslb.com", "i2.hdslb.com"])
        XCTAssertTrue(candidates.allSatisfy { $0.path == url.path && $0.query == url.query })
    }

    func testThirdPartyImageURLIsNeverRewritten() throws {
        let memory = RemoteImageCDNHealthMemory()
        let url = try XCTUnwrap(URL(string: "https://images.example.com/avatar.jpg"))

        let candidates = memory.orderedCandidates(for: [url])

        XCTAssertEqual(candidates, [url])
    }

    func testTransientFailureDemotesHostUntilTTLExpires() throws {
        let memory = RemoteImageCDNHealthMemory(failureTTL: 90)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let url = try XCTUnwrap(URL(string: "https://i0.hdslb.com/bfs/archive/example.jpg"))
        memory.recordTransientFailure(for: url, now: now)

        let duringTTL = memory.orderedCandidates(
            for: [url],
            now: now.addingTimeInterval(30)
        )
        let afterTTL = memory.orderedCandidates(
            for: [url],
            now: now.addingTimeInterval(91)
        )

        XCTAssertEqual(duringTTL.compactMap(\.host), ["i1.hdslb.com", "i2.hdslb.com", "i0.hdslb.com"])
        XCTAssertEqual(afterTTL.first?.host, "i0.hdslb.com")
    }

    func testSuccessRestoresOriginalHostImmediately() throws {
        let memory = RemoteImageCDNHealthMemory(failureTTL: 90)
        let url = try XCTUnwrap(URL(string: "https://i0.hdslb.com/bfs/archive/example.jpg"))
        memory.recordTransientFailure(for: url)
        memory.recordSuccess(for: url)

        let candidates = memory.orderedCandidates(for: [url])

        XCTAssertEqual(candidates.first?.host, "i0.hdslb.com")
    }

    func testOnlyTransientFailuresDemoteImageCDNHost() {
        XCTAssertTrue(RemoteImageCDNFailoverPolicy.shouldDemote(statusCode: 503))
        XCTAssertFalse(RemoteImageCDNFailoverPolicy.shouldDemote(statusCode: 404))
        XCTAssertTrue(RemoteImageCDNFailoverPolicy.shouldDemote(error: URLError(.timedOut)))
        XCTAssertFalse(RemoteImageCDNFailoverPolicy.shouldDemote(error: URLError(.cancelled)))
        XCTAssertEqual(BiliNetworkRetryPolicy.imageFailover.attempts, 1)
        XCTAssertEqual(BiliNetworkRetryPolicy.image.attempts, 2)
    }

    func testDiagnosticsCountsRequestsFailuresAndAutomaticSwitches() throws {
        let memory = RemoteImageCDNHealthMemory(failureTTL: 90)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let originalURL = try XCTUnwrap(URL(string: "https://i0.hdslb.com/bfs/archive/example.jpg"))
        let switchedURL = try XCTUnwrap(URL(string: "https://i1.hdslb.com/bfs/archive/example.jpg"))

        memory.recordRequest(for: originalURL, originalURL: originalURL)
        memory.recordSuccess(for: originalURL)
        memory.recordRequest(for: switchedURL, originalURL: originalURL)
        memory.recordTransientFailure(for: switchedURL, now: now)

        let diagnostics = memory.diagnostics(now: now)
        let originalNode = try XCTUnwrap(diagnostics.hosts.first { $0.host == "i0.hdslb.com" })
        let switchedNode = try XCTUnwrap(diagnostics.hosts.first { $0.host == "i1.hdslb.com" })

        XCTAssertEqual(diagnostics.requestCount, 2)
        XCTAssertEqual(diagnostics.successCount, 1)
        XCTAssertEqual(diagnostics.transientFailureCount, 1)
        XCTAssertEqual(diagnostics.automaticSwitchCount, 1)
        XCTAssertEqual(originalNode.requestCount, 1)
        XCTAssertEqual(originalNode.successCount, 1)
        XCTAssertEqual(switchedNode.requestCount, 1)
        XCTAssertEqual(switchedNode.transientFailureCount, 1)
        XCTAssertEqual(diagnostics.degradedHosts.map(\.host), ["i1.hdslb.com"])
    }

    func testDiagnosticsIgnoreThirdPartyImages() throws {
        let memory = RemoteImageCDNHealthMemory()
        let url = try XCTUnwrap(URL(string: "https://images.example.com/avatar.jpg"))

        memory.recordRequest(for: url, originalURL: url)
        memory.recordSuccess(for: url)
        memory.recordTransientFailure(for: url)

        let diagnostics = memory.diagnostics()

        XCTAssertEqual(diagnostics.requestCount, 0)
        XCTAssertEqual(diagnostics.successCount, 0)
        XCTAssertEqual(diagnostics.transientFailureCount, 0)
        XCTAssertEqual(diagnostics.automaticSwitchCount, 0)
    }

    func testResetDiagnosticsKeepsActiveNodeDemotion() throws {
        let memory = RemoteImageCDNHealthMemory(failureTTL: 90)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let url = try XCTUnwrap(URL(string: "https://i0.hdslb.com/bfs/archive/example.jpg"))
        memory.recordRequest(for: url, originalURL: url)
        memory.recordTransientFailure(for: url, now: now)

        memory.resetDiagnostics()
        let afterDiagnosticReset = memory.diagnostics(now: now)

        XCTAssertEqual(afterDiagnosticReset.requestCount, 0)
        XCTAssertEqual(afterDiagnosticReset.transientFailureCount, 0)
        XCTAssertEqual(afterDiagnosticReset.degradedHosts.map(\.host), ["i0.hdslb.com"])

        memory.reset()
        XCTAssertTrue(memory.diagnostics(now: now).degradedHosts.isEmpty)
    }

    func testDiagnosticsCopyTextIncludesAggregatesWithoutImageURLs() {
        let cache = RemoteImageCacheStatistics(
            memoryEntryCount: 12,
            inFlightCount: 2,
            memoryCostLimit: 64 * 1024 * 1024,
            diskUsage: 2 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024,
            hits: 80,
            misses: 20,
            stores: 16,
            evictions: 3,
            inFlightReuseCount: 9,
            loadTaskCount: 21
        )
        let displayCache = RemoteImageDisplayCacheStatistics(hits: 12, misses: 8)
        let scroll = RemoteImageScrollLoadSuppressionStatistics(
            visibleBypassCount: 7,
            deferredPrefetchCount: 4,
            activeScopeCount: 1
        )
        let cdn = RemoteImageCDNDiagnosticsSnapshot(
            requestCount: 100,
            successCount: 98,
            transientFailureCount: 2,
            automaticSwitchCount: 1,
            hosts: [
                RemoteImageCDNHostDiagnostics(
                    host: "i0.hdslb.com",
                    requestCount: 50,
                    successCount: 49,
                    transientFailureCount: 1
                ),
                RemoteImageCDNHostDiagnostics(
                    host: "i1.hdslb.com",
                    requestCount: 50,
                    successCount: 49,
                    transientFailureCount: 1
                )
            ],
            degradedHosts: [
                RemoteImageCDNDegradedHost(host: "i1.hdslb.com", remainingTime: 42)
            ]
        )

        let text = RemoteImageDiagnosticsTextFormatter.makeText(
            cache: cache,
            displayCache: displayCache,
            scroll: scroll,
            cdn: cdn,
            isDiagnosticsEnabled: true,
            version: "1.0.14",
            build: "48",
            generatedAt: "2026-07-18 12:00"
        )

        XCTAssertTrue(text.contains("version: 1.0.14 (48)"))
        XCTAssertTrue(text.contains("图片加载诊断: 已开启"))
        XCTAssertTrue(text.contains("显示内存缓存"))
        XCTAssertTrue(text.contains("复用进行中加载: 9"))
        XCTAssertTrue(text.contains("新建图片加载任务: 21"))
        XCTAssertTrue(text.contains("滚动中可见请求放行: 7"))
        XCTAssertTrue(text.contains("滚动中后台预取延后: 4"))
        XCTAssertTrue(text.contains("快速滚动负载抑制: 已启用"))
        XCTAssertTrue(text.contains("自动切换: 已启用"))
        XCTAssertTrue(text.contains("i0.hdslb.com: 请求 50 · 成功 49 · 瞬时失败 1 · 失败率 2%"))
        XCTAssertTrue(text.contains("i1.hdslb.com: 剩余 42 秒"))
        XCTAssertFalse(text.contains("https://"))
        XCTAssertFalse(text.contains("example.jpg"))
    }

    @MainActor
    func testDisplayCacheDiagnosticsCountLoadLookups() {
        let cache = RemoteImageDisplayMemoryCache.shared
        cache.clear()
        cache.resetDiagnostics()

        XCTAssertNil(cache.imageForLoad(for: "missing"))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in }
        cache.store(image, for: "cached")
        XCTAssertNotNil(cache.imageForLoad(for: "cached"))

        let statistics = cache.statistics()
        XCTAssertEqual(statistics.hits, 1)
        XCTAssertEqual(statistics.misses, 1)

        cache.clear()
        cache.resetDiagnostics()
    }
}
