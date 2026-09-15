import Foundation
import XCTest

@testable import bili

final class FormalStartupFeatureTests: XCTestCase {
    @MainActor
    func testLibraryStoreRemovesRetiredWarmupAndNetworkExperimentKeys() {
        let defaults = makeUserDefaults()
        let retiredKeys = [
            "cc.bili.home.feedWarmupExperimentEnabled.v1",
            "cc.bili.dynamic.feedWarmupExperimentEnabled.v1",
            "cc.bili.network.pathStabilizationExperimentEnabled.v1",
        ]
        retiredKeys.forEach { defaults.set(false, forKey: $0) }

        _ = LibraryStore(userDefaults: defaults)

        for key in retiredKeys {
            XCTAssertNil(defaults.object(forKey: key))
        }
    }

    func testHomeRecommendDiagnosticsCounterPolicyIncrementsRequestResponseAndFailureCounts() {
        let afterRequest = HomeRecommendDiagnosticsCounterPolicy.recordingRequest(previous: nil)
        XCTAssertEqual(afterRequest, ["request_count": 1])

        let afterSuccess = HomeRecommendDiagnosticsCounterPolicy.recordingResponse(
            previous: afterRequest,
            status: .succeeded
        )
        XCTAssertEqual(afterSuccess["request_count"], 1)
        XCTAssertEqual(afterSuccess["response_count"], 1)
        XCTAssertNil(afterSuccess["failure_count"])

        let afterFailure = HomeRecommendDiagnosticsCounterPolicy.recordingResponse(
            previous: afterSuccess,
            status: .failed
        )
        XCTAssertEqual(afterFailure["response_count"], 2)
        XCTAssertEqual(afterFailure["failure_count"], 1)
    }

    func testHomeRecommendDiagnosticsRequestPolicyRejectsStaleResponses() {
        let currentRequestID = UUID()

        XCTAssertTrue(
            HomeRecommendDiagnosticsRequestPolicy.acceptsResponse(
                currentRequestID: currentRequestID,
                responseRequestID: currentRequestID
            )
        )
        XCTAssertTrue(
            HomeRecommendDiagnosticsRequestPolicy.acceptsResponse(
                currentRequestID: currentRequestID,
                responseRequestID: nil
            )
        )
        XCTAssertFalse(
            HomeRecommendDiagnosticsRequestPolicy.acceptsResponse(
                currentRequestID: currentRequestID,
                responseRequestID: UUID()
            )
        )
    }

    func testLegacyHomeRecommendDiagnosticsSnapshotIgnoresRetiredExperimentState() throws {
        let legacyJSON = Data(
            """
            {
              "status": "idle",
              "source": "app",
              "endpoint": "",
              "profile": "",
              "authMode": "unknown",
              "isLoggedIn": false,
              "guestModeEnabled": false,
              "hasAccessKey": false,
              "hasSESSDATA": false,
              "hasDedeUserID": false,
              "hasBuvid": false,
              "hasBuvidFP": false,
              "identityKey": "",
              "experimentState": {
                "homeFeedWarmupEnabled": false,
                "dynamicFeedWarmupEnabled": false,
                "networkPathStabilizationEnabled": false,
                "sampleGroup": "control"
              }
            }
            """.utf8
        )

        let decoded = try JSONDecoder().decode(HomeRecommendDiagnosticsSnapshot.self, from: legacyJSON)

        XCTAssertEqual(decoded, .empty)
    }

    func testBaselineSnapshotKeepsFirstMarkersAndIncrementsNetworkCounters() {
        var snapshot = StageOneBaselineSnapshot(
            launchStartedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        snapshot.markHomeFirstInteractive(elapsedMilliseconds: 10)
        snapshot.markHomeFirstInteractive(elapsedMilliseconds: 20)
        snapshot.markHomeFirstData(elapsedMilliseconds: 30)
        snapshot.markHomeFirstData(elapsedMilliseconds: 40)
        snapshot.markDynamicFirstData(elapsedMilliseconds: 50)
        snapshot.markDynamicFirstData(elapsedMilliseconds: 60)
        snapshot.markStartupWarmupStarted(elapsedMilliseconds: 70)
        snapshot.markStartupWarmupStarted(elapsedMilliseconds: 80)
        snapshot.markStartupWarmupFinished(elapsedMilliseconds: 90)
        snapshot.markStartupWarmupFinished(elapsedMilliseconds: 100)
        snapshot.recordNetworkRawChange()
        snapshot.recordNetworkRawChange()
        snapshot.recordNetworkRefreshBatch()

        XCTAssertEqual(snapshot.homeFirstInteractiveMilliseconds, 10)
        XCTAssertEqual(snapshot.homeFirstDataMilliseconds, 30)
        XCTAssertEqual(snapshot.dynamicFirstDataMilliseconds, 50)
        XCTAssertEqual(snapshot.startupWarmupStartedMilliseconds, 70)
        XCTAssertEqual(snapshot.startupWarmupFinishedMilliseconds, 90)
        XCTAssertEqual(snapshot.networkRawChangeCount, 2)
        XCTAssertEqual(snapshot.networkRefreshBatchCount, 1)
    }

    func testBaselineHistoryUpsertsCurrentLaunchAndKeepsTwentySessions() {
        var history = StageOneBaselineHistory()

        for index in 0..<21 {
            history.upsert(
                StageOneBaselineSnapshot(
                    launchStartedAt: Date(timeIntervalSince1970: TimeInterval(index))
                )
            )
        }
        var updated = history.snapshots.last!
        updated.recordNetworkRawChange()
        history.upsert(updated)

        XCTAssertEqual(history.snapshots.count, 20)
        XCTAssertEqual(history.snapshots.first?.launchStartedAt, Date(timeIntervalSince1970: 1))
        XCTAssertEqual(history.snapshots.last?.networkRawChangeCount, 1)
    }

    func testNetworkSummaryCalculatesAveragesAndCoalescingRate() {
        var first = StageOneBaselineSnapshot(launchStartedAt: Date(timeIntervalSince1970: 1))
        var second = StageOneBaselineSnapshot(launchStartedAt: Date(timeIntervalSince1970: 2))
        for _ in 0..<4 { first.recordNetworkRawChange() }
        for _ in 0..<2 { first.recordNetworkRefreshBatch() }
        for _ in 0..<2 { second.recordNetworkRawChange() }
        second.recordNetworkRefreshBatch()

        let history = StageOneBaselineHistory(snapshots: [first, second])
        let summary = history.networkSummary()

        XCTAssertEqual(summary.sessionCount, 2)
        XCTAssertEqual(summary.rawChangeCount, 6)
        XCTAssertEqual(summary.refreshBatchCount, 3)
        XCTAssertEqual(summary.averageRawChangeCount, 3, accuracy: 0.001)
        XCTAssertEqual(summary.averageRefreshBatchCount, 1.5, accuracy: 0.001)
        XCTAssertEqual(summary.coalescingRatePercent, 50)
        XCTAssertEqual(
            history.networkSummary(excludingLaunchStartedAt: second.launchStartedAt).sessionCount,
            1
        )
    }

    func testLegacyBaselineSnapshotMapsDeferredWarmupFieldsAndIgnoresExperimentState() throws {
        let legacyJSON = Data(
            """
            {
              "launchStartedAt": 1,
              "experimentState": {
                "homeFeedWarmupEnabled": false,
                "dynamicFeedWarmupEnabled": true,
                "networkPathStabilizationEnabled": false,
                "sampleGroup": "home=off,dynamic=on,network=off"
              },
              "deferredWarmupStartedMilliseconds": 70,
              "deferredWarmupFinishedMilliseconds": 90,
              "networkRawChangeCount": 2,
              "networkRefreshBatchCount": 1
            }
            """.utf8
        )

        let snapshot = try JSONDecoder().decode(StageOneBaselineSnapshot.self, from: legacyJSON)

        XCTAssertEqual(snapshot.startupWarmupStartedMilliseconds, 70)
        XCTAssertEqual(snapshot.startupWarmupFinishedMilliseconds, 90)
        XCTAssertEqual(snapshot.networkRawChangeCount, 2)
        XCTAssertEqual(snapshot.networkRefreshBatchCount, 1)
    }

    @MainActor
    func testPlaybackNetworkRefreshCoordinatorAlwaysCoalescesRapidChanges() async {
        let coordinator = PlaybackNetworkRefreshCoordinator(stabilizationDelay: .milliseconds(20))
        var refreshCount = 0

        for _ in 0..<3 {
            coordinator.submit {
                refreshCount += 1
            }
        }

        try? await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(refreshCount, 1)
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "cc.bili.tests.formal-startup.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}
