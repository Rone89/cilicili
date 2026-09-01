import Foundation
import XCTest
@testable import bili

final class PlaybackStartupRequestSchedulingTests: XCTestCase {
    @MainActor
    func testExpectedPlayURLCancellationDoesNotBecomeAPlaybackFailure() {
        XCTAssertTrue(VideoDetailViewModel.isExpectedPlayURLCancellation(CancellationError()))
        XCTAssertTrue(VideoDetailViewModel.isExpectedPlayURLCancellation(URLError(.cancelled)))
        XCTAssertTrue(
            VideoDetailViewModel.isExpectedPlayURLCancellation(
                NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
            )
        )
        XCTAssertFalse(VideoDetailViewModel.isExpectedPlayURLCancellation(URLError(.timedOut)))
    }

    @MainActor
    func testSchedulerRacesUntilAStartSourceHasEnoughAcceptedSamples() async {
        let scheduler = StartupPlayURLRoutePerformanceStore(
            sampleLimit: 4,
            minimumAcceptedSamples: 3,
            minimumMedianAdvantageMilliseconds: 35
        )

        await scheduler.record(
            route: .webpage,
            networkClass: .wifi,
            elapsedMilliseconds: 260,
            accepted: true
        )
        await scheduler.record(
            route: .wbi,
            networkClass: .wifi,
            elapsedMilliseconds: 100,
            accepted: true
        )

        let decision = await scheduler.decision(networkClass: .wifi, wbiAvailable: true)

        XCTAssertFalse(decision.usesStaggeredFallback)
    }

    @MainActor
    func testSchedulerStaggersTheSlowerSourceAfterLearning() async {
        let scheduler = StartupPlayURLRoutePerformanceStore(
            sampleLimit: 4,
            minimumAcceptedSamples: 3,
            minimumMedianAdvantageMilliseconds: 35
        )

        for elapsedMilliseconds in [280, 300, 290] {
            await scheduler.record(
                route: .webpage,
                networkClass: .wifi,
                elapsedMilliseconds: elapsedMilliseconds,
                accepted: true
            )
        }
        for elapsedMilliseconds in [110, 120, 105] {
            await scheduler.record(
                route: .wbi,
                networkClass: .wifi,
                elapsedMilliseconds: elapsedMilliseconds,
                accepted: true
            )
        }

        let decision = await scheduler.decision(networkClass: .wifi, wbiAvailable: true)

        XCTAssertTrue(decision.usesStaggeredFallback)
        XCTAssertEqual(decision.primaryRoute, .wbi)
        XCTAssertEqual(decision.fallbackRoute, .webpage)
    }

    @MainActor
    func testSchedulerUsesAProvenWinnerBeforeTheFallbackHasSamples() async {
        let scheduler = StartupPlayURLRoutePerformanceStore(
            sampleLimit: 4,
            minimumAcceptedSamples: 3,
            minimumMedianAdvantageMilliseconds: 35
        )

        for elapsedMilliseconds in [110, 120, 105] {
            await scheduler.record(
                route: .wbi,
                networkClass: .wifi,
                elapsedMilliseconds: elapsedMilliseconds,
                accepted: true
            )
        }

        let decision = await scheduler.decision(networkClass: .wifi, wbiAvailable: true)

        XCTAssertTrue(decision.usesStaggeredFallback)
        XCTAssertEqual(decision.primaryRoute, .wbi)
        XCTAssertEqual(decision.fallbackRoute, .webpage)
    }

    @MainActor
    func testSchedulerUsesFullRaceWhenWBIIsUnavailable() async {
        let scheduler = StartupPlayURLRoutePerformanceStore(
            minimumAcceptedSamples: 1,
            minimumMedianAdvantageMilliseconds: 0
        )
        await scheduler.record(
            route: .webpage,
            networkClass: .wifi,
            elapsedMilliseconds: 300,
            accepted: true
        )
        await scheduler.record(
            route: .wbi,
            networkClass: .wifi,
            elapsedMilliseconds: 100,
            accepted: true
        )

        let decision = await scheduler.decision(networkClass: .wifi, wbiAvailable: false)

        XCTAssertFalse(decision.usesStaggeredFallback)
    }

    @MainActor
    func testSchedulerDiagnosticDescribesTheStaggeredRouteOrder() {
        let decision = StartupPlayURLSchedulingDecision(
            primaryRoute: .wbi,
            fallbackRoute: .webpage
        )

        XCTAssertEqual(
            decision.diagnosticMessage,
            "startupScheduler=adaptive mode=staggered primary=wbi fallback=webpage delay=180ms"
        )
    }

    @MainActor
    func testPiliPlusDefersWebpageFallbackUntilWBIFailure() {
        let decision = StartupPlayURLSchedulingDecision(
            primaryRoute: .wbi,
            fallbackRoute: .webpage
        )

        XCTAssertTrue(
            decision.defersWebpageFallbackUntilWBIFailure(piliPlusStyleEnabled: true)
        )
        XCTAssertEqual(
            decision.diagnosticMessage(piliPlusStyleEnabled: true),
            "startupScheduler=adaptive mode=hedged primary=wbi fallback=webpage delay=0ms start=immediate cancel=promptWaiter+underlying"
        )
        XCTAssertEqual(PiliPlusStylePlayURLSelectionExperiment.webpageHedgeDelayNanoseconds, 0)
    }

    @MainActor
    func testRoutingPlanReleasesWebpageOnlyAfterWBIFailure() {
        let plan = StartupPlayURLRoutingPlan(
            schedulingDecision: StartupPlayURLSchedulingDecision(
                primaryRoute: .wbi,
                fallbackRoute: .webpage
            ),
            shouldRaceWBI: true,
            piliPlusStyleEnabled: true
        )

        XCTAssertTrue(plan.startsWebpageHedge)
        XCTAssertEqual(
            plan.deferredFallbackRoute(forUnacceptableResultFrom: .wbi),
            .webpage
        )
        XCTAssertNil(plan.deferredFallbackRoute(forUnacceptableResultFrom: .webpage))
    }

    @MainActor
    func testWebpageOnlyRoutingPlanDoesNotStartWBIOrHedge() {
        let plan = StartupPlayURLRoutingPlan(
            schedulingDecision: .race,
            shouldRaceWBI: false,
            piliPlusStyleEnabled: true
        )

        XCTAssertFalse(plan.shouldRaceWBI)
        XCTAssertFalse(plan.startsWebpageHedge)
        XCTAssertNil(plan.deferredFallbackRoute(forUnacceptableResultFrom: .wbi))
    }

    @MainActor
    func testPiliPlusUsesWBIFirstWhileSchedulerIsStillLearning() {
        let decision = StartupPlayURLSchedulingDecision.race.preferringWBIForPiliPlus(
            piliPlusStyleEnabled: true,
            wbiAvailable: true
        )

        XCTAssertEqual(decision.primaryRoute, .wbi)
        XCTAssertEqual(decision.fallbackRoute, .webpage)
        XCTAssertTrue(decision.defersWebpageFallbackUntilWBIFailure(piliPlusStyleEnabled: true))
    }

    @MainActor
    func testPiliPlusOverridesLearnedWebpagePreference() {
        let decision = StartupPlayURLSchedulingDecision(
            primaryRoute: .webpage,
            fallbackRoute: .wbi
        ).preferringWBIForPiliPlus(
            piliPlusStyleEnabled: true,
            wbiAvailable: true
        )

        XCTAssertEqual(decision.primaryRoute, .wbi)
        XCTAssertEqual(decision.fallbackRoute, .webpage)
        XCTAssertTrue(decision.defersWebpageFallbackUntilWBIFailure(piliPlusStyleEnabled: true))
    }

    @MainActor
    func testPiliPlusKeepsFullRaceWhenWBIIsUnavailable() {
        let decision = StartupPlayURLSchedulingDecision.race.preferringWBIForPiliPlus(
            piliPlusStyleEnabled: true,
            wbiAvailable: false
        )

        XCTAssertFalse(decision.usesStaggeredFallback)
    }

    @MainActor
    func testNonPiliPlusAndWebpagePrimaryKeepStaggeredFallback() {
        let wbiPrimary = StartupPlayURLSchedulingDecision(
            primaryRoute: .wbi,
            fallbackRoute: .webpage
        )
        let webpagePrimary = StartupPlayURLSchedulingDecision(
            primaryRoute: .webpage,
            fallbackRoute: .wbi
        )

        XCTAssertFalse(
            wbiPrimary.defersWebpageFallbackUntilWBIFailure(piliPlusStyleEnabled: false)
        )
        XCTAssertFalse(
            webpagePrimary.defersWebpageFallbackUntilWBIFailure(piliPlusStyleEnabled: true)
        )
        XCTAssertEqual(
            webpagePrimary.diagnosticMessage(piliPlusStyleEnabled: true),
            webpagePrimary.diagnosticMessage
        )
    }

    @MainActor
    func testPerformanceCopyKeepsStartupSchedulerMessage() {
        var session = PlayerPerformanceSession(id: "BVstartupScheduler")
        session.startupSchedulerMessage = "startupScheduler=adaptive mode=race learning"

        let copy = PlayerPerformanceCopyTextFormatter.performanceCopyText(
            metricsID: session.metricsID,
            session: session
        )

        XCTAssertTrue(copy.contains("startupScheduler:\n  startupScheduler=adaptive mode=race learning"))
    }

    @MainActor
    func testStartupSchedulerRetainsEnoughMessagesForWBIRecoveryDiagnostics() {
        XCTAssertGreaterThanOrEqual(
            PlayerPerformanceStore.startupSchedulerDiagnosticPartLimit,
            8
        )
    }

    @MainActor
    func testFallbackTrackerKeepsTheTerminalStatus() async {
        let cancelledBeforeStart = StartupPlayURLFallbackTracker()
        await cancelledBeforeStart.markCancelledBeforeStart()
        await cancelledBeforeStart.markStarted()
        let cancelledStatus = await cancelledBeforeStart.currentStatus()

        XCTAssertEqual(cancelledStatus, .cancelledBeforeStart)

        let started = StartupPlayURLFallbackTracker()
        await started.markStarted()
        await started.markCancelledBeforeStart()
        let startedStatus = await started.currentStatus()

        XCTAssertEqual(startedStatus, .started)
    }

    @MainActor
    func testDeferredFallbackTracksSuccessAndWBIFailureSeparately() async {
        let notNeeded = StartupPlayURLFallbackTracker(initialStatus: .deferred)
        await notNeeded.markNotNeeded()
        await notNeeded.markStartedAfterWBIFailure()
        let notNeededStatus = await notNeeded.currentStatus()

        XCTAssertEqual(notNeededStatus, .notNeeded)

        let started = StartupPlayURLFallbackTracker(initialStatus: .deferred)
        await started.markStartedAfterWBIFailure()
        await started.markNotNeeded()
        let startedStatus = await started.currentStatus()

        XCTAssertEqual(startedStatus, .startedAfterWBIFailure)
    }

    @MainActor
    func testExpiredRequestLeaseRejectsLateSchedulerFeedback() async {
        let scheduler = StartupPlayURLRoutePerformanceStore(
            minimumAcceptedSamples: 1,
            minimumMedianAdvantageMilliseconds: 0
        )
        let requestLease = StartupPlayURLRequestLease()
        requestLease.invalidate()

        let recorded = await scheduler.record(
            route: .wbi,
            networkClass: .wifi,
            elapsedMilliseconds: 18_437,
            accepted: true,
            requestLease: requestLease
        )
        let decision = await scheduler.decision(networkClass: .wifi, wbiAvailable: true)

        XCTAssertFalse(recorded)
        XCTAssertFalse(StartupPlayURLFeedbackEligibility.allows(requestLease))
        XCTAssertFalse(decision.usesStaggeredFallback)
    }

    @MainActor
    func testPreloadRequestsDoNotRecordSchedulerFeedback() {
        XCTAssertTrue(StartupPlayURLRequestSource.foreground.recordsSchedulerFeedback)
        XCTAssertFalse(StartupPlayURLRequestSource.preload.recordsSchedulerFeedback)
    }

    @MainActor
    func testSharedTaskWaiterCancelsWithoutCancellingUnderlyingRequest() async throws {
        let underlying = Task<Int, Error> {
            try await Task.sleep(for: .milliseconds(80))
            return 42
        }
        let waiter = Task<Int, Error> {
            try await BiliAPIClient.awaitSharedTask(underlying)
        }

        waiter.cancel()
        do {
            _ = try await waiter.value
            XCTFail("Cancelled waiter should throw")
        } catch is CancellationError {
            // Expected: cancellation belongs to this waiter, not the shared request.
        }

        let underlyingValue = try await underlying.value
        XCTAssertEqual(underlyingValue, 42)
    }

    @MainActor
    func testWBIHealthRequiresTwoFailuresBeforeSuppression() async {
        let health = StartupWBIHealthStore(
            failureThreshold: 2,
            failureWindow: 20,
            suppressionDuration: 30
        )

        let first = await health.recordFailure(reason: "network.-1001", now: 100)
        let statusAfterFirst = await health.suppressionStatus(now: 101)
        let second = await health.recordFailure(reason: "network.-1001", now: 102)
        let statusAfterSecond = await health.suppressionStatus(now: 103)

        XCTAssertEqual(first, .observed(consecutiveFailures: 1))
        XCTAssertNil(statusAfterFirst)
        XCTAssertEqual(
            second,
            .suppressed(
                StartupWBISuppressionStatus(
                    reason: "network.-1001",
                    remainingMilliseconds: 30_000
                )
            )
        )
        XCTAssertEqual(statusAfterSecond?.reason, "network.-1001")
        XCTAssertEqual(statusAfterSecond?.remainingMilliseconds, 29_000)
    }

    @MainActor
    func testWBIHealthSuccessResetsPendingFailureStreak() async {
        let health = StartupWBIHealthStore(
            failureThreshold: 2,
            failureWindow: 20,
            suppressionDuration: 30
        )

        _ = await health.recordFailure(reason: "api.-403", now: 100)
        let didReset = await health.recordSuccess()
        let nextFailure = await health.recordFailure(reason: "api.-403", now: 101)

        XCTAssertTrue(didReset)
        XCTAssertEqual(nextFailure, .observed(consecutiveFailures: 1))
    }

    @MainActor
    func testContentSpecificEmptyPlayURLDoesNotSuppressWBIForOtherVideos() {
        XCTAssertNil(
            BiliAPIClient.startupWBIHealthFailureReason(for: BiliAPIError.emptyPlayURL)
        )
        XCTAssertNil(
            BiliAPIClient.startupWBIHealthFailureReason(
                for: BiliAPIError.unsupportedHardwarePlayback("AV1")
            )
        )
        XCTAssertEqual(
            BiliAPIClient.startupWBIHealthFailureReason(for: URLError(.timedOut)),
            "network.-1001"
        )
    }

    @MainActor
    func testPiliPlusCompatibilityRescueRejectsUnrelatedAPIErrors() {
        XCTAssertTrue(BiliAPIClient.shouldRescuePiliPlusWBI(after: BiliAPIError.emptyPlayURL))
        XCTAssertFalse(BiliAPIClient.shouldRescuePiliPlusWBI(after: BiliAPIError.emptyData))
        XCTAssertFalse(
            BiliAPIClient.shouldRescuePiliPlusWBI(
                after: BiliAPIError.api(code: -352, message: "risk control")
            )
        )
    }

    @MainActor
    func testWBIRouteHintIsScopedAndExpires() async {
        let store = StartupWBIRouteHintStore(duration: 10)
        let key = StartupWBIRouteHintKey(
            bvid: "BVrouteHint",
            cid: 1,
            requestedQuality: 116,
            accountMID: 42,
            credentialVersion: 3
        )
        let otherAccount = StartupWBIRouteHintKey(
            bvid: key.bvid,
            cid: key.cid,
            requestedQuality: key.requestedQuality,
            accountMID: 43,
            credentialVersion: key.credentialVersion
        )
        let otherCID = StartupWBIRouteHintKey(
            bvid: key.bvid,
            cid: 2,
            requestedQuality: key.requestedQuality,
            accountMID: key.accountMID,
            credentialVersion: key.credentialVersion
        )
        let otherCredential = StartupWBIRouteHintKey(
            bvid: key.bvid,
            cid: key.cid,
            requestedQuality: key.requestedQuality,
            accountMID: key.accountMID,
            credentialVersion: 4
        )

        await store.store(.webpageOnly, for: key, now: 100)
        let storedHint = await store.hint(for: key, now: 109)
        let otherAccountHint = await store.hint(for: otherAccount, now: 109)
        let otherCIDHint = await store.hint(for: otherCID, now: 109)
        let otherCredentialHint = await store.hint(for: otherCredential, now: 109)
        let recoveredHint = await store.hint(for: key, now: 111)

        let webpageOnlyPlan = StartupPlayURLRoutingPlan(
            schedulingDecision: .race,
            shouldRaceWBI: storedHint != .webpageOnly,
            piliPlusStyleEnabled: true
        )
        let recoveredPlan = StartupPlayURLRoutingPlan(
            schedulingDecision: .race,
            shouldRaceWBI: recoveredHint != .webpageOnly,
            piliPlusStyleEnabled: true
        )

        XCTAssertEqual(storedHint, .webpageOnly)
        XCTAssertNil(otherAccountHint)
        XCTAssertNil(otherCIDHint)
        XCTAssertNil(otherCredentialHint)
        XCTAssertNil(recoveredHint)
        XCTAssertFalse(webpageOnlyPlan.shouldRaceWBI)
        XCTAssertTrue(recoveredPlan.shouldRaceWBI)
    }

    @MainActor
    func testWBIRouteHintCanClearOneVideoWithoutAffectingAnother() async {
        let store = StartupWBIRouteHintStore(duration: 10)
        let first = StartupWBIRouteHintKey(
            bvid: "BVfirst",
            cid: 1,
            requestedQuality: 116,
            accountMID: nil,
            credentialVersion: 1
        )
        let second = StartupWBIRouteHintKey(
            bvid: "BVsecond",
            cid: 2,
            requestedQuality: 116,
            accountMID: nil,
            credentialVersion: 1
        )
        await store.store(.webpageOnly, for: first, now: 100)
        await store.store(.compatibilityWBI, for: second, now: 100)

        await store.clear(containing: first.bvid)
        let firstHint = await store.hint(for: first, now: 101)
        let secondHint = await store.hint(for: second, now: 101)

        XCTAssertNil(firstHint)
        XCTAssertEqual(secondHint, .compatibilityWBI)
    }

    @MainActor
    func testPiliPlusSampleGroupingSeparatesSchedulerVersions() {
        XCTAssertEqual(
            PiliPlusStylePlayURLSelectionExperiment.sampleGroupStrategy(
                startupSchedulerMessage: "strategy=piliPlusConditionalWBIRescueV17",
                isEnabled: true
            ).key,
            "piliPlusConditionalWBIRescueV17"
        )
        XCTAssertEqual(
            PiliPlusStylePlayURLSelectionExperiment.sampleGroupStrategy(
                startupSchedulerMessage: "strategy=piliPlusPromptWinnerCancellationV16",
                isEnabled: true
            ).key,
            "piliPlusPromptWinnerCancellationV16"
        )
        XCTAssertEqual(
            PiliPlusStylePlayURLSelectionExperiment.sampleGroupStrategy(
                startupSchedulerMessage: "strategy=piliPlusBaseQualitySelectionV15",
                isEnabled: true
            ).key,
            "piliPlusBaseQualitySelectionV15"
        )
        XCTAssertEqual(
            PiliPlusStylePlayURLSelectionExperiment.sampleGroupStrategy(
                startupSchedulerMessage: "strategy=piliPlusWBIResponseDiagnosticsV13",
                isEnabled: true
            ).key,
            "piliPlusWBIResponseDiagnosticsV13"
        )
        XCTAssertEqual(
            PiliPlusStylePlayURLSelectionExperiment.sampleGroupStrategy(
                startupSchedulerMessage: "strategy=piliPlusStreamingWebpagePlayInfoV11",
                isEnabled: true
            ).key,
            "piliPlusStreamingWebpagePlayInfoV11"
        )
        XCTAssertEqual(
            PiliPlusStylePlayURLSelectionExperiment.sampleGroupStrategy(
                startupSchedulerMessage: "strategy=piliPlusScopedWBIHealthV10",
                isEnabled: true
            ).key,
            "piliPlusScopedWBIHealthV10"
        )
        XCTAssertEqual(
            PiliPlusStylePlayURLSelectionExperiment.sampleGroupStrategy(
                startupSchedulerMessage: "strategy=piliPlusCancellableWebpageHedgeV9",
                isEnabled: true
            ).key,
            "piliPlusCancellableWebpageHedgeV9"
        )
        XCTAssertEqual(
            PiliPlusStylePlayURLSelectionExperiment.sampleGroupStrategy(
                startupSchedulerMessage: "strategy=piliPlusBaseQualityWBIWebpageRaceV8",
                isEnabled: true
            ).key,
            "piliPlusBaseQualityWBIWebpageRaceV8"
        )
        XCTAssertEqual(
            PiliPlusStylePlayURLSelectionExperiment.sampleGroupStrategy(
                startupSchedulerMessage: "strategy=piliPlusStandardWBIWebpageRaceV7",
                isEnabled: true
            ).key,
            "piliPlusStandardWBIWebpageRaceV7"
        )
        XCTAssertEqual(
            PiliPlusStylePlayURLSelectionExperiment.sampleGroupStrategy(
                startupSchedulerMessage: "strategy=piliPlusStandardWBIRaceV6",
                isEnabled: true
            ).key,
            "piliPlusStandardWBIRaceV6"
        )
        XCTAssertEqual(
            PiliPlusStylePlayURLSelectionExperiment.sampleGroupStrategy(
                startupSchedulerMessage: "strategy=piliPlusLegacyFirstFallbackV5",
                isEnabled: true
            ).key,
            "piliPlusLegacyFirstFallbackV5"
        )
        XCTAssertEqual(
            PiliPlusStylePlayURLSelectionExperiment.sampleGroupStrategy(
                startupSchedulerMessage: "strategy=piliPlusStaggeredRescueV4",
                isEnabled: true
            ).key,
            "piliPlusStaggeredRescueV4"
        )
        XCTAssertEqual(
            PiliPlusStylePlayURLSelectionExperiment.sampleGroupStrategy(
                startupSchedulerMessage: "route=singleWBIBaseQ80",
                isEnabled: true
            ).key,
            "piliPlusSingleResponseV1"
        )
        XCTAssertEqual(
            PiliPlusStylePlayURLSelectionExperiment.sampleGroupStrategy(
                startupSchedulerMessage: "route=singleWBITargetQ",
                isEnabled: true
            ).key,
            "piliPlusTargetRaceV2"
        )
        XCTAssertEqual(
            PiliPlusStylePlayURLSelectionExperiment.sampleGroupStrategy(
                startupSchedulerMessage: "strategy=piliPlusTargetRescueV3",
                isEnabled: true
            ).key,
            "piliPlusTargetRescueV3"
        )
        let currentStrategy = PiliPlusStylePlayURLSelectionExperiment.sampleGroupStrategy(
            startupSchedulerMessage: "strategy=\(PiliPlusStylePlayURLSelectionExperiment.currentStrategyKey)",
            isEnabled: true
        )
        XCTAssertEqual(currentStrategy.key, PiliPlusStylePlayURLSelectionExperiment.currentStrategyKey)
        XCTAssertEqual(currentStrategy.title, "取流策略：V18")

        let fallbackDeadlineStrategy = PiliPlusStylePlayURLSelectionExperiment.sampleGroupStrategy(
            startupSchedulerMessage:
                "strategy=\(PiliPlusStylePlayURLSelectionExperiment.currentStrategyKey) fallbackDeadline=on",
            isEnabled: true
        )
        XCTAssertEqual(
            fallbackDeadlineStrategy.key,
            PlayableFallbackDeadlineExperiment.strategyKey
        )
        XCTAssertEqual(fallbackDeadlineStrategy.title, "取流策略：V18 + 降级限时实验")
    }

    @MainActor
    func testPiliPlusWebpageHedgeDiagnosticIncludesCancellationPhase() {
        let message = BiliAPIClient.piliPlusWebpageHedgeDiagnosticMessage(
            event: "webpageHedgeCancelled",
            delayMilliseconds: 0,
            elapsedMilliseconds: 112,
            phase: "inFlight",
            requestElapsedMilliseconds: 22
        )

        XCTAssertTrue(message.contains("event=webpageHedgeCancelled"))
        XCTAssertTrue(message.contains("strategy=\(PiliPlusStylePlayURLSelectionExperiment.currentStrategyKey)"))
        XCTAssertTrue(message.contains("delay=0ms"))
        XCTAssertTrue(message.contains("phase=inFlight"))
        XCTAssertTrue(message.contains("request=22ms"))
    }

    @MainActor
    func testPiliPlusWebpageStreamDiagnosticIncludesSavedBytes() {
        let message = BiliAPIClient.piliPlusWebpageStreamDiagnosticMessage(
            mode: "incremental",
            receivedBytes: 120_000,
            expectedBytes: 500_000,
            elapsedMilliseconds: 210
        )

        XCTAssertTrue(message.contains("mode=incremental"))
        XCTAssertTrue(message.contains("strategy=\(PiliPlusStylePlayURLSelectionExperiment.currentStrategyKey)"))
        XCTAssertTrue(message.contains("received=120000"))
        XCTAssertTrue(message.contains("expected=500000"))
        XCTAssertTrue(message.contains("saved=380000"))
    }
}
