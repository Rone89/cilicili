import XCTest
@testable import bili

final class ResourceLoadingExperimentTests: XCTestCase {
    func testRemainingExperimentsCanBeDisabledIndividually() {
        let defaults = makeUserDefaults()

        XCTAssertEqual(
            ResourceLoadingExperiment.resumeWarmupWait(normalBudget: 0.12, userDefaults: defaults),
            0.22,
            accuracy: 0.001
        )

        defaults.set(false, forKey: ResourceLoadingExperiment.Feature.resumePacketWarmup.storageKey)
        XCTAssertFalse(ResourceLoadingExperiment.isFeatureEnabled(.resumePacketWarmup, in: defaults))
        XCTAssertEqual(
            ResourceLoadingExperiment.resumeWarmupWait(normalBudget: 0.12, userDefaults: defaults),
            0.12,
            accuracy: 0.001
        )
    }

    func testReadRequestCoalescerSharesOneConcurrentOperation() async throws {
        let coalescer = BiliReadRequestCoalescer()
        let counter = RequestCounter()

        let request: @Sendable () async throws -> Data = {
            try await coalescer.data(for: "same-read") {
                await counter.increment()
                try await Task.sleep(nanoseconds: 40_000_000)
                return Data("shared".utf8)
            }
        }

        async let first: Data = request()
        async let second: Data = request()
        let values = try await (first, second)
        let requestCount = await counter.value

        XCTAssertEqual(values.0, Data("shared".utf8))
        XCTAssertEqual(values.1, Data("shared".utf8))
        XCTAssertEqual(requestCount, 1)
    }

    func testDiagnosticsSummarizeEventsWithoutRequestIdentity() {
        let diagnostics = ResourceLoadingDiagnostics(
            maximumEventCount: 2,
            shouldRecord: { true }
        )

        diagnostics.record(.firstScreenWindow, durationMilliseconds: 950)
        diagnostics.record(.backgroundPreloadDeferred, durationMilliseconds: 700)
        diagnostics.record(.readRequestOwner, durationMilliseconds: 120)
        diagnostics.record(.readRequestShared, durationMilliseconds: 90)
        diagnostics.record(.dynamicSnapshotSaved, value: 4_096)
        diagnostics.record(.resumeWarmupHit, durationMilliseconds: 80)

        let snapshot = diagnostics.snapshot()
        XCTAssertEqual(snapshot.firstScreenWindowCount, 1)
        XCTAssertEqual(snapshot.backgroundPreloadDeferredCount, 1)
        XCTAssertEqual(snapshot.averageBackgroundPreloadDeferredMilliseconds, 700)
        XCTAssertEqual(snapshot.readRequestOwnerCount, 1)
        XCTAssertEqual(snapshot.readRequestSharedCount, 1)
        XCTAssertEqual(snapshot.averageReadRequestMilliseconds, 105)
        XCTAssertEqual(snapshot.dynamicSnapshotSavedBytes, 4_096)
        XCTAssertEqual(snapshot.resumeWarmupHitCount, 1)
        XCTAssertEqual(snapshot.events.count, 2)
        XCTAssertFalse(snapshot.events.contains { $0.details.keys.contains("request") })

        diagnostics.reset()
        XCTAssertEqual(diagnostics.snapshot(), .empty)
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "cc.bili.tests.resource-loading.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}

private actor RequestCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    var value: Int { count }
}
