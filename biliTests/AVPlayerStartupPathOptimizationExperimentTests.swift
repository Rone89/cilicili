import XCTest
@testable import bili

final class AVPlayerStartupPathOptimizationExperimentTests: XCTestCase {
    @MainActor
    func testStartupPathIsAlwaysEnabledAndCapsPlayerCreationWaitAtFortyMilliseconds() {
        let defaults = makeUserDefaults()
        defaults.set(false, forKey: AVPlayerStartupPathOptimizationExperiment.storageKey)
        XCTAssertTrue(AVPlayerStartupPathOptimizationExperiment.stored(in: defaults))
        XCTAssertEqual(
            AVPlayerStartupPathOptimizationExperiment.playerCreationWarmupWait(
                normalBudget: 0.16,
                userDefaults: defaults
            ),
            0.04,
            accuracy: 0.001
        )
        XCTAssertEqual(
            AVPlayerStartupPathOptimizationExperiment.playerCreationWarmupWait(
                normalBudget: 0.02,
                userDefaults: defaults
            ),
            0.02,
            accuracy: 0.001
        )
    }

    @MainActor
    func testPiliPlusStylePlayURLSelectionIsAlwaysEnabled() {
        let defaults = makeUserDefaults()
        defaults.set(false, forKey: PiliPlusStylePlayURLSelectionExperiment.storageKey)
        XCTAssertTrue(PiliPlusStylePlayURLSelectionExperiment.stored(in: defaults))
    }

    @MainActor
    func testPendingTaskDeadlineReturnsBeforeSlowTaskCompletes() async {
        let slowTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        let clock = ContinuousClock()
        let startedAt = clock.now

        let didFinish = await PendingTaskDeadline.finishes(
            slowTask,
            within: 20_000_000
        )

        slowTask.cancel()
        XCTAssertFalse(didFinish)
        XCTAssertLessThan(startedAt.duration(to: clock.now), .milliseconds(250))
    }

    @MainActor
    func testPendingTaskDeadlineDoesNotCancelSharedTaskAfterTimeout() async {
        let sharedTask = Task {
            try? await Task.sleep(nanoseconds: 60_000_000)
            return !Task.isCancelled
        }

        let didFinish = await PendingTaskDeadline.finishes(
            sharedTask,
            within: 10_000_000
        )

        XCTAssertFalse(didFinish)
        let completedWithoutCancellation = await sharedTask.value
        XCTAssertTrue(completedWithoutCancellation)
    }

    @MainActor
    func testStartupPacketWarmupRequiresBothVideoAndAudio() {
        XCTAssertTrue(HLSStartupPacketWarmupResult(videoReady: true, audioReady: true).isReady)
        XCTAssertFalse(HLSStartupPacketWarmupResult(videoReady: true, audioReady: false).isReady)
        XCTAssertFalse(HLSStartupPacketWarmupResult(videoReady: false, audioReady: true).isReady)
        XCTAssertEqual(
            HLSStartupPacketWarmupResult(videoReady: true, audioReady: false).diagnosticState,
            "video=ready audio=skip"
        )
    }

    @MainActor
    func testPerformanceCopyReportsStartupExperimentState() {
        var session = PlayerPerformanceSession(id: "BVstartupExperiment")
        session.avPlayerStartupPathOptimizationExperimentEnabled = true
        session.piliPlusStylePlayURLSelectionExperimentEnabled = true
        session.startupGapMessage = "open>detail 20ms | detail>url 45ms | url>player 8ms"
        session.playURLMilliseconds = 181

        let copy = PlayerPerformanceCopyTextFormatter.performanceCopyText(
            metricsID: session.metricsID,
            session: session
        )

        XCTAssertTrue(copy.contains("startupPathOptimization: on"))
        XCTAssertTrue(copy.contains("piliPlusStyleAV1PlayURLSelection: on"))
        XCTAssertTrue(copy.contains("startupGaps:\n  open>detail 20ms | detail>url 45ms | url>player 8ms"))
        let fullLog = PlayerPerformanceCopyTextFormatter.performanceLogCopyText(
            sessions: [session],
            sampleGroups: []
        )
        XCTAssertTrue(fullLog.contains("CiliCili 播放性能日志"))
        XCTAssertTrue(fullLog.contains("startupPathOptimization: on"))
        XCTAssertTrue(fullLog.contains("piliPlusStyleAV1PlayURLSelection: on"))
        XCTAssertEqual(
            AVPlayerStartupPathOptimizationExperiment.sampleGroupStateTitle(for: nil),
            "启动链路：旧样本未知"
        )
        XCTAssertEqual(
            PiliPlusStylePlayURLSelectionExperiment.sampleGroupStateTitle(for: nil),
            "PiliPlus AV1 取流：旧样本未知"
        )
    }

    @MainActor
    func testPerformanceLogOmitsPurePrebuildSession() {
        var prebuild = PlayerPerformanceSession(id: "BVprebuild")
        prebuild.manifestStageMessage = "plannedVideo=q80"
        prebuild.networkMessage = "host=api.bilibili.com path=playurl"

        var playback = PlayerPerformanceSession(id: "BVplayback")
        playback.playURLMilliseconds = 180

        let log = PlayerPerformanceCopyTextFormatter.performanceLogCopyText(
            sessions: [prebuild, playback],
            sampleGroups: []
        )

        XCTAssertTrue(log.contains("sessions: 1"))
        XCTAssertTrue(log.contains("metricsID: BVplayback"))
        XCTAssertFalse(log.contains("metricsID: BVprebuild"))
    }

    @MainActor
    func testPerformanceCopyUsesStartupCodecAndRedactsSignedURLs() {
        var session = PlayerPerformanceSession(id: "BVstartupCodec")
        session.startupCodec = "av01.0.08M.08.0.110.01.01.01.0"
        session.playbackRecoveryMessage = "retry=https://upos.example.test/video.m4s?token=secret"

        let copy = PlayerPerformanceCopyTextFormatter.performanceCopyText(
            metricsID: session.metricsID,
            session: session
        )

        XCTAssertTrue(copy.contains("codec: av01.0.08M.08.0.110.01.01.01.0"))
        XCTAssertTrue(copy.contains("URL[host=upos.example.test]"))
        XCTAssertFalse(copy.contains("token=secret"))
    }

    @MainActor
    func testStartupMedianUsesBothMiddleSamples() {
        XCTAssertEqual(PlayerPerformanceSampleGroup.median([500, 1_500]), 1_000)
        XCTAssertEqual(PlayerPerformanceSampleGroup.median([100, 500, 1_500]), 500)
        XCTAssertNil(PlayerPerformanceSampleGroup.median([]))
    }

    @MainActor
    func testPerformanceTestPlaybackOptionsDisableHistoryAndStartupCaches() {
        XCTAssertFalse(VideoDetailPlaybackOptions.performanceTest.recordsPlaybackHistory)
        XCTAssertFalse(VideoDetailPlaybackOptions.performanceTest.resumesPlaybackHistory)
        XCTAssertFalse(VideoDetailPlaybackOptions.performanceTest.usesStartupCaches)
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "cc.bili.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}
