import XCTest
@testable import bili

@MainActor
final class LivePlaybackExperimentsTests: XCTestCase {
    func testDefaultLiveQualityUses1080PBlueRay() {
        XCTAssertEqual(LiveStreamQuality.defaultPreferredQN, 400)
    }

    func testLiveHLSFastStartKeepsShortBufferForDirectLiveStream() {
        XCTAssertTrue(
            LiveHLSFastStartPolicy.activatesForDirectLiveHLS(
                isDirectLiveHLS: true,
                isLiveStream: true
            )
        )
        XCTAssertFalse(
            LiveHLSFastStartPolicy.activatesForDirectLiveHLS(
                isDirectLiveHLS: true,
                isLiveStream: false
            )
        )
        XCTAssertFalse(
            LiveHLSFastStartPolicy.activatesForDirectLiveHLS(
                isDirectLiveHLS: false,
                isLiveStream: true
            )
        )
    }

    func testLiveHLSFastStartUsesImmediatePlaybackOnlyBeforeFirstFrame() {
        XCTAssertTrue(
            LiveHLSFastStartPolicy.usesImmediatePlayback(
                isDirectLiveHLS: true,
                isLiveStream: true,
                isStartupFastStartActive: true
            )
        )
        XCTAssertFalse(
            LiveHLSFastStartPolicy.usesImmediatePlayback(
                isDirectLiveHLS: true,
                isLiveStream: true,
                isStartupFastStartActive: false
            )
        )
        XCTAssertFalse(
            LiveHLSFastStartPolicy.usesImmediatePlayback(
                isDirectLiveHLS: false,
                isLiveStream: true,
                isStartupFastStartActive: true
            )
        )
    }

    func testTransportStreamDefersInitialLiveEdgeSeek() {
        XCTAssertTrue(LiveHLSFastStartPolicy.defersInitialLiveEdgeSeek(streamFormat: "ts"))
        XCTAssertTrue(LiveHLSFastStartPolicy.defersInitialLiveEdgeSeek(streamFormat: "HTTP_TS"))
        XCTAssertFalse(LiveHLSFastStartPolicy.defersInitialLiveEdgeSeek(streamFormat: "fmp4"))
        XCTAssertFalse(LiveHLSFastStartPolicy.defersInitialLiveEdgeSeek(streamFormat: nil))
    }

    func testSlowStartupRouteSwitchUsesEarlyConsistentThreshold() {
        XCTAssertEqual(LivePlaybackPolicy.slowStartupThresholdMilliseconds, 2_200)
        XCTAssertEqual(LivePlaybackPolicy.slowStartupRouteSwitchDelayMilliseconds, 2_200)
        XCTAssertEqual(
            LivePlaybackPolicy.slowStartupRouteSwitchDelayNanoseconds,
            2_200_000_000
        )
    }

    func testLiveStartupAuxiliaryDefersOnlyForTransportStreamStartup() {
        XCTAssertTrue(
            LiveStartupAuxiliaryPolicy.defersUntilFirstFrame(
                streamFormat: "ts"
            )
        )
        XCTAssertFalse(
            LiveStartupAuxiliaryPolicy.defersUntilFirstFrame(
                streamFormat: "fmp4"
            )
        )
        XCTAssertFalse(
            LiveStartupAuxiliaryPolicy.defersUntilFirstFrame(
                streamFormat: nil
            )
        )
    }

    func testLiveRoomUsesFullscreenOnlyForLandscapeLiveVideo() {
        XCTAssertTrue(
            LiveRoomVideoDetailLayoutPolicy.usesLandscapeFullscreen(
                isLandscape: true,
                videoAspectRatio: 16.0 / 9.0
            )
        )
        XCTAssertFalse(
            LiveRoomVideoDetailLayoutPolicy.usesLandscapeFullscreen(
                isLandscape: false,
                videoAspectRatio: 16.0 / 9.0
            )
        )
        XCTAssertFalse(
            LiveRoomVideoDetailLayoutPolicy.usesLandscapeFullscreen(
                isLandscape: true,
                videoAspectRatio: 9.0 / 16.0
            )
        )
        XCTAssertFalse(
            LiveRoomVideoDetailLayoutPolicy.usesLandscapeFullscreen(
                isLandscape: true,
                videoAspectRatio: nil
            )
        )

        XCTAssertTrue(
            LiveRoomVideoDetailLayoutPolicy.supportsLandscapeFullscreen(
                videoAspectRatio: 16.0 / 9.0
            )
        )
        XCTAssertFalse(
            LiveRoomVideoDetailLayoutPolicy.supportsLandscapeFullscreen(
                videoAspectRatio: 9.0 / 16.0
            )
        )
    }

    func testLiveRoomFullscreenModeFollowsTheActualVideoDirection() {
        XCTAssertEqual(
            LiveRoomVideoDetailLayoutPolicy.fullscreenMode(videoAspectRatio: 16.0 / 9.0),
            .landscape
        )
        XCTAssertEqual(
            LiveRoomVideoDetailLayoutPolicy.fullscreenMode(videoAspectRatio: 9.0 / 16.0),
            .portrait
        )
        XCTAssertEqual(
            LiveRoomVideoDetailLayoutPolicy.fullscreenMode(videoAspectRatio: 1.0),
            .unavailable
        )
        XCTAssertEqual(
            LiveRoomVideoDetailLayoutPolicy.fullscreenMode(videoAspectRatio: nil),
            .unavailable
        )
        XCTAssertTrue(
            LiveRoomVideoDetailLayoutPolicy.supportsPortraitFullscreen(
                videoAspectRatio: 9.0 / 16.0
            )
        )
        XCTAssertFalse(
            LiveRoomVideoDetailLayoutPolicy.supportsPortraitFullscreen(
                videoAspectRatio: 16.0 / 9.0
            )
        )
    }

    func testSimpleLiveLayoutReservesDetailAndSafeAreaBeforeSizingPlayer() {
        let tallPlayerHeight = LiveRoomSimpleLiveLayoutPolicy.playerHeight(
            containerSize: CGSize(width: 420, height: 912),
            safeAreaTop: 59,
            safeAreaBottom: 34,
            videoAspectRatio: 9.0 / 16.0
        )
        XCTAssertEqual(tallPlayerHeight, 533)
        XCTAssertLessThanOrEqual(
            tallPlayerHeight
                + 59
                + 34
                + LiveRoomSimpleLiveLayoutPolicy.minimumDetailHeight,
            912
        )

        let compactPlayerHeight = LiveRoomSimpleLiveLayoutPolicy.playerHeight(
            containerSize: CGSize(width: 375, height: 667),
            safeAreaTop: 47,
            safeAreaBottom: 34,
            videoAspectRatio: 9.0 / 16.0
        )
        XCTAssertEqual(compactPlayerHeight, 300)
    }

    func testRotationSurfaceStabilityPolicyHidesChatHostForTheWholeTransition() {
        let policy = LiveRotationSurfaceStabilityPolicy()

        XCTAssertTrue(policy.hidesContentHost(duringTransitionToLandscape: true))
        XCTAssertTrue(policy.hidesContentHost(duringTransitionToLandscape: false))
        XCTAssertFalse(policy.allowsContentHostInteraction(duringTransitionToLandscape: false))
        XCTAssertTrue(policy.retainsChromeTree())
    }

    func testRotationSurfaceAlignmentStateRecordsTransitionAndPresentationSize() {
        let state = LiveRotationSurfaceAlignmentState()

        state.setBareSurfaceTransitionActive(true)
        state.recordOverlayDeferred()
        state.recordChatDeferred()
        state.setBareSurfaceTransitionActive(false)
        state.recordOverlayFlush()
        state.recordChatFlush()
        state.updatePresentationSize(CGSize(width: 1080, height: 1920))

        let snapshot = state.snapshot
        XCTAssertFalse(snapshot.isBareSurfaceTransitionActive)
        XCTAssertEqual(snapshot.rotationTransitionCount, 1)
        XCTAssertEqual(snapshot.overlayDeferredCount, 1)
        XCTAssertEqual(snapshot.overlayFlushCount, 1)
        XCTAssertEqual(snapshot.chatDeferredCount, 1)
        XCTAssertEqual(snapshot.chatFlushCount, 1)
        XCTAssertEqual(snapshot.presentationSizeText, "1080x1920")
        XCTAssertEqual(snapshot.videoAspectRatio ?? 0, 0.5625, accuracy: 0.0001)
    }

    func testAdaptiveStartupMovesRecentlyFailedEquivalentHostBehindHealthyHost() {
        let memory = LiveStreamStartupHealthMemory()
        let failed = makeCandidate(host: "slow.example.com")
        let healthy = makeCandidate(host: "fast.example.com")

        memory.recordStartupFailure(for: failed)

        let ordered = memory.orderedStartupCandidates([failed, healthy])

        XCTAssertEqual(ordered.map { $0.url.host }, ["fast.example.com", "slow.example.com"])
    }

    func testAdaptiveStartupKeepsOriginalOrderAfterHostRecovers() {
        let memory = LiveStreamStartupHealthMemory()
        let recovered = makeCandidate(host: "recovered.example.com")
        let healthy = makeCandidate(host: "fast.example.com")
        memory.recordStartupFailure(for: recovered)
        memory.recordStartupSuccess(for: recovered)

        let ordered = memory.orderedStartupCandidates([recovered, healthy])

        XCTAssertEqual(ordered.map { $0.url.host }, ["recovered.example.com", "fast.example.com"])
    }

    func testAdaptiveStartupReordersOnlyTheMatchingStreamProfile() {
        let memory = LiveStreamStartupHealthMemory()
        let otherProfile = makeCandidate(host: "other.example.com", quality: 400)
        let failed = makeCandidate(host: "slow.example.com")
        let healthy = makeCandidate(host: "fast.example.com")
        memory.recordStartupFailure(for: failed)

        let ordered = memory.orderedStartupCandidates([otherProfile, failed, healthy])

        XCTAssertEqual(
            ordered.map { $0.url.host },
            ["other.example.com", "fast.example.com", "slow.example.com"]
        )
    }

    func testAdaptiveStartupMovesRecentlySlowEquivalentHostBehindHealthyHost() {
        let memory = LiveStreamStartupHealthMemory()
        let slow = makeCandidate(host: "slow.example.com")
        let healthy = makeCandidate(host: "fast.example.com")

        memory.recordStartupResult(for: slow, firstFrameMilliseconds: 7_200)

        let ordered = memory.orderedStartupCandidates([slow, healthy])

        XCTAssertEqual(ordered.map { $0.url.host }, ["fast.example.com", "slow.example.com"])
        XCTAssertEqual(memory.snapshot(for: slow)?.slowStartCount, 1)
        XCTAssertEqual(memory.snapshot(for: slow)?.recentFirstFrameMilliseconds, 7_200)
    }

    func testSlowStartupRouteSwitchUsesDistinctEquivalentTSHost() {
        let primary = makeCandidate(host: "slow.example.com", format: "ts")
        let fallback = makeCandidate(host: "fast.example.com", format: "ts")

        let plan = LiveSlowStartupRouteSwitchPlan.make(
            candidates: [primary, fallback],
            primaryIndex: 0
        )

        XCTAssertEqual(plan, LiveSlowStartupRouteSwitchPlan(primaryIndex: 0, fallbackIndex: 1))
    }

    func testSlowStartupRouteSwitchDoesNotReplaceFMP4WithAnotherRoute() {
        let primary = makeCandidate(host: "primary.example.com", format: "fmp4")
        let fallback = makeCandidate(host: "fallback.example.com", format: "fmp4")

        let plan = LiveSlowStartupRouteSwitchPlan.make(
            candidates: [primary, fallback],
            primaryIndex: 0
        )

        XCTAssertNil(plan)
    }

    private func makeCandidate(
        host: String,
        quality: Int = 10000,
        format: String = "fmp4"
    ) -> LiveStreamURLCandidate {
        LiveStreamURLCandidate(
            url: URL(string: "https://\(host)/live-bvc/123/live.m3u8")!,
            protocolName: "http_hls",
            formatName: format,
            codecName: "avc",
            currentQN: quality,
            qualityTitle: "原画",
            source: "v2"
        )
    }
}
