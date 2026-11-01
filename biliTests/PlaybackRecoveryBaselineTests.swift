import XCTest
@testable import bili

final class PlaybackRecoveryBaselineTests: XCTestCase {
    func testUnavailableEvidenceIsNotReportedAsUnbufferedOrZeroSeconds() {
        let value = baseline(target: 30, ranges: nil)
        XCTAssertEqual(value.bufferState, .unknown)
        XCTAssertNil(value.bufferAheadSeconds)
        XCTAssertTrue(value.diagnosticText.contains("loadedAheadSeconds=-"))
    }

    func testObservedEmptyRangesMeanNoLoadedTargetButDoNotProveCacheMiss() {
        let value = baseline(target: 30, ranges: [])
        XCTAssertEqual(value.bufferState, .uncovered)
        XCTAssertEqual(value.bufferAheadSeconds, 0)
        XCTAssertTrue(value.diagnosticText.contains("mediaCacheState=unknown"))
    }

    func testMergesOverlappingAndAdjacentRangesWithoutDoubleCounting() {
        let value = baseline(target: 12, ranges: [
            .init(start: 20, end: 25), .init(start: 10, end: 18),
            .init(start: 15, end: 20), .init(start: 10, end: 11),
        ])
        XCTAssertEqual(value.bufferState, .covered)
        XCTAssertEqual(value.bufferAheadSeconds, 13)
    }

    func testDoesNotCountDisjointFutureRangesAsPlayableAhead() {
        let ranges = [PlayerBufferedRange(start: 10, end: 20), .init(start: 20.01, end: 40)]
        XCTAssertEqual(baseline(target: 15, ranges: ranges).bufferAheadSeconds, 5)
        XCTAssertEqual(baseline(target: 20.005, ranges: ranges).bufferState, .uncovered)
    }

    func testRangeEndIsExcludedAndNextRangeStartIsIncluded() {
        let ranges = [PlayerBufferedRange(start: 10, end: 20)]
        XCTAssertEqual(baseline(target: 10, ranges: ranges).bufferState, .covered)
        XCTAssertEqual(baseline(target: 20, ranges: ranges).bufferState, .uncovered)
    }

    func testInvalidTargetsAndMalformedRangesRemainUnknown() {
        let valid = [PlayerBufferedRange(start: 0, end: 60)]
        let invalidTargets: [Double?] = [nil, .nan, .infinity, -1]
        for target in invalidTargets {
            XCTAssertEqual(baseline(target: target, ranges: valid).bufferState, .unknown)
        }
        for range in [
            PlayerBufferedRange(start: .nan, end: 60),
            .init(start: 0, end: .infinity),
            .init(start: -1, end: 60), .init(start: 30, end: 20),
        ] {
            XCTAssertEqual(baseline(target: 30, ranges: [range]).bufferState, .unknown)
        }
    }

    func testIndependentOperationsHaveDistinctIDsAndKeepPausedScenario() {
        let first = baseline(target: 30, ranges: [])
        let second = baseline(target: 30, ranges: [])
        XCTAssertNotEqual(first.sampleID, second.sampleID)
        XCTAssertTrue(first.diagnosticText.contains("mode=seekPaused"))
        XCTAssertTrue(first.diagnosticText.contains("requestedTargetSeconds=30.000"))
    }

    @MainActor
    func testPausedSliderCapturesRangesBeforeSeekAndNeverStartsPlayback() async throws {
        let coordinator = ActivePlaybackCoordinator.shared
        coordinator.stopActivePlayback()
        let engine = PlayerLifecycleEngineSpy(isPlaying: false)
        engine.snapshotBufferObservationAvailable = true
        engine.snapshotBufferedRanges = [.init(start: 20, end: 40)]
        engine.bufferedRangesAfterSeek = []
        let metricsID = UUID().uuidString
        let player = PlayerStateViewModel(videoURL: nil, audioURL: nil,
            title: "Paused seek baseline", referer: "https://www.bilibili.com",
            durationHint: 60, metricsID: metricsID, engine: engine)
        let surface = VideoSurfaceContainerView()
        player.attachSurface(surface, prefersNativePlaybackControls: false)
        coordinator.activate(player)
        defer { player.stop(); coordinator.stopActivePlayback() }

        player.setPlaybackIntent(false)
        player.seekAfterSliderCommit(to: 0.5)
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline,
              PlayerPerformanceStore.shared.session(for: metricsID)?.seekMessage?.contains("sampleID=") != true {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let message = try XCTUnwrap(PlayerPerformanceStore.shared.session(for: metricsID)?.seekMessage)
        XCTAssertTrue(message.contains("mode=seekPaused"))
        XCTAssertTrue(message.contains("targetLoadedRange=covered"))
        XCTAssertTrue(message.contains("loadedAheadSeconds=10.000"))
        XCTAssertEqual(engine.snapshotBufferedRanges, [])
        XCTAssertEqual(engine.playCallCount, 0)
        XCTAssertFalse(player.isPlaying)
    }

    @MainActor
    func testExportRetainsThreeResumeCyclesAndSeparatesExportFromSampleBuild() throws {
        let store = PlayerPerformanceStore.shared
        let metricsID = UUID().uuidString
        for sample in 1...3 {
            for stage in ["paused", "playRequested", "transportPlaying", "firstAdvancingFrame"] {
                store.record(.manualResumeRecovery, metricsID: metricsID,
                    message: "stage=\(stage) sampleID=cycle\(sample) sampleBuild=previous-build")
            }
        }
        let session = try XCTUnwrap(store.session(for: metricsID))
        let copy = PlayerPerformanceCopyTextFormatter.performanceCopyText(metricsID: metricsID, session: session)
        for sample in 1...3 {
            XCTAssertTrue(copy.contains("stage=playRequested sampleID=cycle\(sample)"))
            XCTAssertTrue(copy.contains("stage=firstAdvancingFrame sampleID=cycle\(sample)"))
        }
        let export = PlayerPerformanceCopyTextFormatter.performanceLogCopyText(sessions: [], sampleGroups: [])
        XCTAssertTrue(export.contains("exportRunID:"))
        XCTAssertTrue(export.contains("exportApp:"))
        XCTAssertTrue(copy.contains("sampleBuild=previous-build"))
    }

    private func baseline(target: Double?, ranges: [PlayerBufferedRange]?) -> PlaybackRecoveryBaseline {
        PlaybackRecoveryBaseline(mode: "seekPaused", networkClass: "wifi", targetTime: target, ranges: ranges)
    }
}
