import XCTest
import UIKit
@testable import bili

final class PlaybackRecoveryTestReportTests: XCTestCase {
    func testMetricParserKeepsOnlyAllowedFieldsAndNeverExportsCredentialsOrURLs() throws {
        let metric = try XCTUnwrap(PlaybackRecoveryTestMetric.parse(
            kind: "manualResume",
            message: "stage=firstAdvancingFrame sampleID=abc playToFrame=42ms cookie=secret token=secret source=https://cdn.invalid/path?token=secret",
            receivedMilliseconds: 100
        ))
        XCTAssertEqual(metric.fields["playToFrame"], "42ms")
        XCTAssertNil(metric.fields["cookie"])
        XCTAssertNil(metric.fields["token"])
        XCTAssertNil(metric.fields["source"])
        let text = String(decoding: try JSONEncoder().encode(metric), as: UTF8.self)
        XCTAssertFalse(text.contains("secret"))
        XCTAssertFalse(text.contains("cdn.invalid"))
    }

    func testParserRejectsNonfiniteTimesAndDoesNotInventMissingLatencies() throws {
        XCTAssertNil(PlaybackRecoveryTestMetric.parse(kind: "seek", message: "sampleID=abc", receivedMilliseconds: .nan))
        let metric = try XCTUnwrap(PlaybackRecoveryTestMetric.parse(
            kind: "manualResume", message: "stage=firstAdvancingFrame sampleID=abc playToFrame=NaNms pauseToFrame=-1ms",
            receivedMilliseconds: 1
        ))
        XCTAssertNil(metric.fields["playToFrame"])
        XCTAssertNil(metric.fields["pauseToFrame"])
        XCTAssertNil(PlaybackRecoveryTestMetric.parse(kind: "seek", message: "scrub source=native", receivedMilliseconds: 1))
        XCTAssertNil(PlaybackRecoveryTestMetric.parse(kind: "seek", message: "bufferReady coverage=100", receivedMilliseconds: 1))
    }

    func testDiskRoundTripKeepsAllTrialDataAndRejectsStaleRevisions() async throws {
        let url = temporaryURL()
        let disk = PlaybackRecoveryTestReportDisk(url: url)
        var newer = PlaybackRecoveryTestReport(context: ["build": "47"], plannedTrialCount: 21)
        newer.trials = [PlaybackRecoveryTestTrial(id: UUID(), scenario: .pause120, repetition: 3)]
        try await disk.write(newer, revision: 2)
        let stale = PlaybackRecoveryTestReport(context: ["build": "old"], plannedTrialCount: 0)
        try await disk.write(stale, revision: 1)
        let saved = try await disk.read()
        XCTAssertEqual(saved?.exportText, newer.exportText)
        let data = try Data(contentsOf: url)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("pause120"))
    }

    func testFailedNewerWriteStillPreventsAnOlderWriteReplacingExistingReport() async throws {
        let url = temporaryURL()
        let disk = PlaybackRecoveryTestReportDisk(url: url)
        let original = PlaybackRecoveryTestReport(context: ["build": "47"], plannedTrialCount: 21)
        try await disk.write(original, revision: 1)
        let oversized = PlaybackRecoveryTestReport(context: ["oversized": String(repeating: "a", count: 1_048_577)], plannedTrialCount: 21)
        do {
            try await disk.write(oversized, revision: 3)
            XCTFail("Oversized report must fail")
        } catch {}
        let stale = PlaybackRecoveryTestReport(context: ["build": "stale"], plannedTrialCount: 0)
        try await disk.write(stale, revision: 2)
        let afterFailure = try await disk.read()
        XCTAssertEqual(afterFailure?.exportText, original.exportText)
        var retry = original
        retry.status = "completed"
        try await disk.write(retry, revision: 3)
        let afterRetry = try await disk.read()
        XCTAssertEqual(afterRetry?.exportText, retry.exportText)
    }

    @MainActor
    func testOldRunCannotOverwriteNewRunAndWriteFailureKeepsCopyableData() async throws {
        let disk = RecoveryScriptMemoryDisk()
        let store = PlaybackRecoveryTestReportStore(disk: disk)
        let first = PlaybackRecoveryTestReport(context: [:], plannedTrialCount: 21)
        let second = PlaybackRecoveryTestReport(context: ["run": "new"], plannedTrialCount: 21)
        store.begin(first)
        store.begin(second)
        store.update(first)
        XCTAssertEqual(store.report?.runID, second.runID)
        await disk.setFailure(true)
        var final = second
        final.status = "completed"
        store.update(final)
        await store.flush()
        XCTAssertNotNil(store.persistenceError)
        XCTAssertEqual(store.report?.status, "completed")
        XCTAssertFalse(store.report?.exportText.isEmpty ?? true)
    }

    @MainActor
    func testRelaunchConvertsUnfinishedRunIntoInterruptedReport() async throws {
        let url = temporaryURL()
        var report = PlaybackRecoveryTestReport(context: [:], plannedTrialCount: 21)
        report.trials = [PlaybackRecoveryTestTrial(id: UUID(), scenario: .pause120, repetition: 2)]
        try await PlaybackRecoveryTestReportDisk(url: url).write(report, revision: 1)
        let store = PlaybackRecoveryTestReportStore(disk: PlaybackRecoveryTestReportDisk(url: url))
        let deadline = Date().addingTimeInterval(5)
        while store.report == nil, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(store.report?.runID, report.runID)
        XCTAssertEqual(store.report?.status, "interrupted")
        XCTAssertEqual(store.report?.trials.last?.outcome, "interrupted")
        await store.flush()
    }

    @MainActor
    func testRealDriverRestoresPreviousIdleTimerSetting() {
        let original = UIApplication.shared.isIdleTimerDisabled
        defer { UIApplication.shared.isIdleTimerDisabled = original }
        let player = PlayerStateViewModel(
            videoURL: nil, audioURL: nil, title: "Idle timer lease",
            referer: "https://www.bilibili.com", engine: PlayerLifecycleEngineSpy(isPlaying: false)
        )
        defer { player.stop() }
        let driver = PlayerRecoveryTestDriver(player: player, metricsID: UUID().uuidString)
        UIApplication.shared.isIdleTimerDisabled = false
        driver.setTestingActive(true)
        XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled)
        driver.setTestingActive(false)
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled)
        UIApplication.shared.isIdleTimerDisabled = true
        driver.setTestingActive(true)
        driver.setTestingActive(false)
        XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled)
    }

    private func temporaryURL() -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appending(path: "latest.json")
    }
}
