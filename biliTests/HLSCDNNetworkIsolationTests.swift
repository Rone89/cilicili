import Foundation
import XCTest
@testable import bili

@MainActor
final class HLSCDNNetworkIsolationTests: XCTestCase {
    func testHostScoresDoNotCrossNetworkClasses() async throws {
        let cache = try makeCache()
        let urls = try makeURLs()
        await cache.recordResult(url: urls[1], for: urls, elapsedMilliseconds: 30,
                                 bytes: 1024, succeeded: true, networkClass: .wifi)
        let wifi = await cache.preferredURLs(for: urls, networkClass: .wifi)
        let cellular = await cache.preferredURLs(for: urls, networkClass: .cellular)
        let constrained = await cache.preferredURLs(for: urls, networkClass: .constrained)
        XCTAssertEqual(wifi.first, urls[1])
        XCTAssertEqual(cellular, urls)
        XCTAssertEqual(constrained, urls)
    }

    func testPreferredURLAndHostSetFallbackAreNetworkScoped() async throws {
        let cache = try makeCache()
        let urls = try makeURLs()
        await cache.recordPreferredURL(urls[1], for: urls, networkClass: .wifi)
        let refreshed = urls.map { $0.appendingPathComponent("refreshed") }
        let wifi = await cache.preferredURLs(for: refreshed, networkClass: .wifi)
        let cellular = await cache.preferredURLs(for: refreshed, networkClass: .cellular)
        XCTAssertEqual(wifi.first, refreshed[1])
        XCTAssertEqual(cellular, refreshed)
    }

    func testAvoidanceAndSuccessfulRecoveryStayInTheirNetworkContext() async throws {
        let cache = try makeCache()
        let urls = try makeURLs()
        await cache.recordSessionAvoidance(host: urls[0].host, reason: "test", metricsID: nil, networkClass: .wifi)
        let wifi = await cache.diagnostics(for: urls, networkClass: .wifi)
        let cellular = await cache.diagnostics(for: urls, networkClass: .cellular)
        XCTAssertEqual(wifi.first?.host, urls[1].host)
        XCTAssertEqual(wifi.first(where: { $0.host == urls[0].host })?.isSessionAvoided, true)
        XCTAssertTrue(cellular.allSatisfy { !$0.isSessionAvoided })

        // A request finishing in a different context must not clear Wi-Fi avoidance.
        await cache.recordResult(url: urls[0], for: urls, elapsedMilliseconds: 10,
                                 bytes: 128, succeeded: true, networkClass: .cellular)
        let stillAvoided = await cache.diagnostics(for: urls, networkClass: .wifi)
        XCTAssertEqual(stillAvoided.first(where: { $0.host == urls[0].host })?.isSessionAvoided, true)
        await cache.recordResult(url: urls[0], for: urls, elapsedMilliseconds: 10,
                                 bytes: 128, succeeded: true, networkClass: .wifi)
        let recovered = await cache.diagnostics(for: urls, networkClass: .wifi)
        XCTAssertEqual(recovered.first(where: { $0.host == urls[0].host })?.isSessionAvoided, false)
    }

    func testCancellationDoesNotPenalizeHost() async throws {
        let cache = try makeCache()
        let urls = try makeURLs()
        await cache.recordFailure(url: urls[0], for: urls, elapsedMilliseconds: 800,
                                  error: CancellationError(), networkClass: .wifi)
        let diagnostics = await cache.diagnostics(for: urls, networkClass: .wifi)
        XCTAssertTrue(diagnostics.allSatisfy { $0.failureCount == 0 && !$0.isSessionAvoided })
    }

    func testUnscopedPersistedPreferenceIsNotMigratedToEveryNetwork() async throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = try makeURLs()
        let stale = ["host|" + urls.compactMap(\.host).joined(separator: "|"):
                        LegacyEntry(preferredURLString: urls[1].absoluteString, date: Date())]
        try JSONEncoder().encode(stale).write(to: directory.appendingPathComponent("HLSSourcePreferenceCache.json"))
        let cache = HLSSourcePreferenceCache(directory: directory)
        for network in [PlaybackEnvironment.NetworkClass.wifi, .cellular, .constrained, .unknown] {
            let selected = await cache.preferredURLs(for: urls, networkClass: network)
            XCTAssertEqual(selected, urls)
        }
    }

    private struct LegacyEntry: Encodable {
        let preferredURLString: String
        let date: Date
    }

    private func makeCache() throws -> HLSSourcePreferenceCache {
        HLSSourcePreferenceCache(directory: temporaryDirectory())
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("HLSCDNIsolation-\(UUID().uuidString)")
    }

    private func makeURLs() throws -> [URL] {
        let id = UUID().uuidString.lowercased()
        return [try XCTUnwrap(URL(string: "https://primary-\(id).invalid/video.m4s")),
                try XCTUnwrap(URL(string: "https://backup-\(id).invalid/video.m4s"))]
    }
}
