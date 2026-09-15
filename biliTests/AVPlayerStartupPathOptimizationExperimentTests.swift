import XCTest

@testable import bili

final class AVPlayerStartupPathOptimizationExperimentTests: XCTestCase {
    @MainActor
    func testStartupPathAndImmediatePlayerCreationAreAlwaysEnabled() {
        XCTAssertTrue(AVPlayerStartupPathOptimizationExperiment.stored())
        XCTAssertEqual(
            AVPlayerStartupPathOptimizationExperiment.playerCreationWarmupWait(
                normalBudget: 0.16
            ),
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            AVPlayerStartupPathOptimizationExperiment.playerCreationWarmupWait(
                normalBudget: 0.02
            ),
            0,
            accuracy: 0.001
        )
    }

    @MainActor
    func testImmediatePlayerCreationModeUsesStableSampleGroupKeys() {
        XCTAssertEqual(
            AVPlayerStartupPathOptimizationExperiment.playerCreationMode(
                "immediateCreateExperiment"
            ).key,
            "immediateCreate"
        )
        XCTAssertEqual(
            AVPlayerStartupPathOptimizationExperiment.playerCreationMode("packetGate").key,
            "packetGate"
        )
        XCTAssertEqual(
            AVPlayerStartupPathOptimizationExperiment.playerCreationMode(nil).key,
            "unknown"
        )
    }

    func testRelatedEarlyPlayURLPrefetchOnlyAllowsUnconstrainedWiFi() {
        let wifi = PlaybackEnvironment(
            networkClass: .wifi,
            isLowPowerModeEnabled: false,
            isThermallyConstrained: false,
            thermalPressure: .nominal
        )
        let cellular = PlaybackEnvironment(
            networkClass: .cellular,
            isLowPowerModeEnabled: false,
            isThermallyConstrained: false,
            thermalPressure: .nominal
        )
        let lowPower = PlaybackEnvironment(
            networkClass: .wifi,
            isLowPowerModeEnabled: true,
            isThermallyConstrained: false,
            thermalPressure: .nominal
        )
        let thermal = PlaybackEnvironment(
            networkClass: .wifi,
            isLowPowerModeEnabled: false,
            isThermallyConstrained: true,
            thermalPressure: .elevated
        )

        XCTAssertTrue(RelatedPlaybackEarlyPlayURLPrefetchPolicy.isEligible(environment: wifi))
        XCTAssertFalse(RelatedPlaybackEarlyPlayURLPrefetchPolicy.isEligible(environment: cellular))
        XCTAssertFalse(RelatedPlaybackEarlyPlayURLPrefetchPolicy.isEligible(environment: lowPower))
        XCTAssertFalse(RelatedPlaybackEarlyPlayURLPrefetchPolicy.isEligible(environment: thermal))
    }

    func testRelatedEarlyPlayURLPrefetchDiagnosticIncludesDispositionAndLead() {
        let trace = RelatedPlaybackEarlyPlayURLPrefetchTrace(
            disposition: .joined,
            startedAt: Date(timeIntervalSince1970: 100)
        )
        XCTAssertEqual(
            trace.leadMilliseconds(at: Date(timeIntervalSince1970: 100.375)),
            375
        )
        XCTAssertEqual(
            RelatedPlaybackEarlyPlayURLPrefetchPolicy.diagnosticMessage(
                event: "consumed",
                targetBVID: "BVRelatedPrefetch",
                disposition: trace.disposition,
                leadMilliseconds: 375
            ),
            "relatedEarlyPlayURLPrefetch event=consumed target=BVRelatedPrefetch result=joined mediaWarm=off lead=375ms"
        )
    }

    func testRelatedStartupPackageWarmupOnlyAllowsUnconstrainedWiFi() {
        let wifi = PlaybackEnvironment(
            networkClass: .wifi,
            isLowPowerModeEnabled: false,
            isThermallyConstrained: false,
            thermalPressure: .nominal
        )
        let cellular = PlaybackEnvironment(
            networkClass: .cellular,
            isLowPowerModeEnabled: false,
            isThermallyConstrained: false,
            thermalPressure: .nominal
        )
        let lowPower = PlaybackEnvironment(
            networkClass: .wifi,
            isLowPowerModeEnabled: true,
            isThermallyConstrained: false,
            thermalPressure: .nominal
        )
        let thermal = PlaybackEnvironment(
            networkClass: .wifi,
            isLowPowerModeEnabled: false,
            isThermallyConstrained: true,
            thermalPressure: .elevated
        )

        XCTAssertTrue(RelatedPlaybackStartupPackageWarmupPolicy.isEligible(environment: wifi))
        XCTAssertFalse(RelatedPlaybackStartupPackageWarmupPolicy.isEligible(environment: cellular))
        XCTAssertFalse(RelatedPlaybackStartupPackageWarmupPolicy.isEligible(environment: lowPower))
        XCTAssertFalse(RelatedPlaybackStartupPackageWarmupPolicy.isEligible(environment: thermal))
    }

    func testRelatedStartupPackageWarmupDiagnosticIncludesPackageStateAndLead() {
        let trace = RelatedPlaybackStartupPackageWarmupTrace(
            disposition: .started,
            startedAt: Date(timeIntervalSince1970: 100)
        )
        XCTAssertEqual(trace.leadMilliseconds(at: Date(timeIntervalSince1970: 100.425)), 425)
        XCTAssertEqual(
            RelatedPlaybackStartupPackageWarmupPolicy.diagnosticMessage(
                event: "consumed",
                targetBVID: "BVRelatedWarmup",
                result: trace.disposition.rawValue,
                packageState: VideoStartupPackageWarmupWaitResult.ready.rawValue,
                leadMilliseconds: 425
            ),
            "relatedStartupPackageWarmup event=consumed target=BVRelatedWarmup result=started package=ready lead=425ms"
        )
    }

    func testPlayableFallbackDeadlineOnlyAppliesToEnabledPlayableFallback() {
        XCTAssertFalse(
            PlayableFallbackDeadlineExperiment.allowsEarlyReturn(
                isEnabled: false,
                hasPlayableFallback: true
            )
        )
        XCTAssertFalse(
            PlayableFallbackDeadlineExperiment.allowsEarlyReturn(
                isEnabled: true,
                hasPlayableFallback: false
            )
        )
        XCTAssertTrue(
            PlayableFallbackDeadlineExperiment.allowsEarlyReturn(
                isEnabled: true,
                hasPlayableFallback: true
            )
        )
    }

    func testPendingTaskDeadlineReturnsFastValueAndTimesOutSlowValue() async throws {
        let fastValue = try await PendingTaskDeadline.value(within: 100_000_000) {
            42
        }
        let clock = ContinuousClock()
        let startedAt = clock.now
        let slowValue = try await PendingTaskDeadline.value(within: 25_000_000) {
            await withCheckedContinuation { continuation in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) {
                    continuation.resume()
                }
            }
            return 42
        }

        XCTAssertEqual(fastValue, 42)
        XCTAssertNil(slowValue)
        XCTAssertLessThan(startedAt.duration(to: clock.now), .milliseconds(150))
    }

    @MainActor
    func testZeroDeadlineDoesNotCancelBackgroundWarmupTask() async {
        let backgroundWarmup = Task {
            try? await Task.sleep(nanoseconds: 20_000_000)
            return !Task.isCancelled
        }

        let didFinish = await PendingTaskDeadline.finishes(
            backgroundWarmup,
            within: 0
        )

        XCTAssertFalse(didFinish)
        let completedWithoutCancellation = await backgroundWarmup.value
        XCTAssertTrue(completedWithoutCancellation)
    }

    @MainActor
    func testStartupPackagePrebuildReturnsImmediatelyWhenWarmupWaitIsZero() async {
        let preloadCenter = VideoPreloadCenter.shared
        await preloadCenter.cancelMediaWarmups(clearCache: true)
        defer {
            Task {
                await preloadCenter.cancelMediaWarmups(clearCache: true)
            }
        }
        let variant = PlayVariant(
            quality: 80,
            title: "1080P",
            videoURL: URL(string: "https://example.test/video.m4s"),
            audioURL: nil,
            videoStream: nil,
            audioStream: nil,
            codec: "avc1.640028",
            resolution: "1920x1080",
            frameRate: "30",
            bandwidth: 1_000_000,
            isHDR: false,
            badge: nil
        )
        let clock = ContinuousClock()
        let startedAt = clock.now

        let result = await preloadCenter.prebuildStartupPackageAndWait(
            variant: variant,
            targetVariant: nil,
            bvid: "BVImmediatePlayerCreationTest",
            cid: 1,
            page: nil,
            durationHint: nil,
            cdnPreference: .automatic,
            timeout: 0
        )

        XCTAssertEqual(result, .deferred)
        XCTAssertLessThan(startedAt.duration(to: clock.now), .milliseconds(250))
    }

    @MainActor
    func testStartupSampleGroupsSeparateImmediateCreationFromPacketGate() {
        let store = PlayerPerformanceStore.shared
        store.clear()
        defer { store.clear() }

        store.record(
            .manifestStage,
            metricsID: "BVImmediateCreationGroup",
            message: "startupWarmWait=deferred mode=immediateCreateExperiment 0ms budget=0ms codec=AV1"
        )
        store.record(
            .startupBreakdown,
            metricsID: "BVImmediateCreationGroup",
            message: "total=1000ms q=80 cdn=automatic network=wifi source=network codec=AV1"
        )
        store.record(
            .manifestStage,
            metricsID: "BVPacketGateGroup",
            message: "startupWarmWait=timeout mode=packetGate 40ms budget=40ms codec=AV1"
        )
        store.record(
            .startupBreakdown,
            metricsID: "BVPacketGateGroup",
            message: "total=1000ms q=80 cdn=automatic network=wifi source=network codec=AV1"
        )

        let groups = store.startupSampleGroups(limit: 8)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(Set(groups.map(\.playerCreationModeKey)), ["immediateCreate", "packetGate"])
        XCTAssertEqual(
            Set(groups.map(\.playerCreationModeTitle)),
            ["播放器：即时创建", "播放器：40ms 预热门槛"]
        )
    }

    @MainActor
    func testStartupSampleGroupsMarkPromotedRelatedPreloadsEnabled() {
        let store = PlayerPerformanceStore.shared
        store.clear()
        defer { store.clear() }

        store.record(
            .startupBreakdown,
            metricsID: "BVRelatedPreloadFormal",
            message: "total=1000ms q=80 cdn=automatic network=wifi source=network codec=AV1"
        )

        let groups = store.startupSampleGroups(limit: 8)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.relatedEarlyPlayURLPrefetchExperimentEnabled, true)
        XCTAssertEqual(groups.first?.relatedStartupPackageWarmupExperimentEnabled, true)
    }

    @MainActor
    func testPiliPlusStylePlayURLSelectionExperimentIsAlwaysEnabled() {
        XCTAssertTrue(PiliPlusStylePlayURLSelectionExperiment.stored())
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
        session.startupPlayerCreationMode = "immediateCreateExperiment"
        session.piliPlusStylePlayURLSelectionExperimentEnabled = true
        session.relatedEarlyPlayURLPrefetchExperimentEnabled = true
        session.relatedStartupPackageWarmupExperimentEnabled = true
        session.startupGapMessage = "open>detail 20ms | detail>url 45ms | url>player 8ms"
        session.playURLMilliseconds = 181

        let copy = PlayerPerformanceCopyTextFormatter.performanceCopyText(
            metricsID: session.metricsID,
            session: session
        )

        XCTAssertTrue(copy.contains("startupPathOptimization: on"))
        XCTAssertTrue(copy.contains("playerCreationMode: immediateCreate"))
        XCTAssertTrue(copy.contains("piliPlusStyleAV1PlayURLSelection: on"))
        XCTAssertTrue(copy.contains("relatedEarlyPlayURLPrefetch: 相关推荐早取：已启用"))
        XCTAssertTrue(copy.contains("relatedStartupPackageWarmup: 相关推荐首包：已启用"))
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

}
