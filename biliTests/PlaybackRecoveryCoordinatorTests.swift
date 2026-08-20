import XCTest
@testable import bili

final class PlaybackRecoveryCoordinatorTests: XCTestCase {
    @MainActor
    func testAuthDeniedReloadsPlayURLWithoutCDNRefresh() {
        var coordinator = VideoDetailPlaybackRecoveryCoordinator()
        let decision = coordinator.receiveFailure(input(reason: reason(.authDenied, statusCode: 403)))

        XCTAssertEqual(decision.action, .reloadPlayURL)
        XCTAssertTrue(decision.shouldHandleFailure)
        XCTAssertTrue(decision.shouldMarkFailedVariant)
        XCTAssertFalse(decision.shouldRefreshCDN)
    }

    @MainActor
    func testRateLimitedReloadsPlayURLAndRefreshesCDN() {
        var coordinator = VideoDetailPlaybackRecoveryCoordinator()
        let decision = coordinator.receiveFailure(input(reason: reason(.rateLimited, statusCode: 429)))

        XCTAssertEqual(decision.action, .reloadPlayURL)
        XCTAssertTrue(decision.shouldRefreshCDN)
    }

    @MainActor
    func testURLExpiredReloadsPlayURLEvenWhenFallbackExists() {
        var coordinator = VideoDetailPlaybackRecoveryCoordinator()
        let decision = coordinator.receiveFailure(input(reason: reason(.urlExpired, statusCode: 412)))

        XCTAssertEqual(decision.action, .reloadPlayURL)
        XCTAssertFalse(decision.shouldRefreshCDN)
    }

    @MainActor
    func testURLExpiredIsIgnoredWhilePlayURLReloadIsAlreadyInFlight() {
        var coordinator = VideoDetailPlaybackRecoveryCoordinator()
        let decision = coordinator.receiveFailure(input(
            reason: reason(.urlExpired, statusCode: 412),
            hasFallbackVariant: true,
            playURLIsLoading: true
        ))

        XCTAssertEqual(decision.action, .ignore(.playURLReloadInFlight))
        XCTAssertFalse(decision.shouldHandleFailure)
        XCTAssertFalse(decision.shouldMarkFailedVariant)
    }

    @MainActor
    func testReloadMessageIsIgnoredWhilePlayURLReloadIsAlreadyInFlight() {
        var coordinator = VideoDetailPlaybackRecoveryCoordinator()
        let decision = coordinator.receiveFailure(input(
            message: "播放地址已过期，正在重新获取播放地址",
            reason: reason(.network),
            hasFallbackVariant: true,
            playURLIsLoading: true
        ))

        XCTAssertEqual(decision.action, .ignore(.playURLReloadInFlight))
        XCTAssertFalse(decision.shouldHandleFailure)
    }

    @MainActor
    func testCancelledFailureIsIgnored() {
        var coordinator = VideoDetailPlaybackRecoveryCoordinator()
        let decision = coordinator.receiveFailure(input(reason: reason(.cancelled)))

        XCTAssertEqual(decision.action, .ignore(.cancelled))
        XCTAssertFalse(decision.shouldHandleFailure)
        XCTAssertFalse(decision.shouldMarkFailedVariant)
    }

    @MainActor
    func testDuplicateFailureIsIgnoredAcrossSources() {
        var coordinator = VideoDetailPlaybackRecoveryCoordinator()
        let first = coordinator.receiveFailure(input(source: .playerCallback, reason: reason(.timeout)))
        let duplicate = coordinator.receiveFailure(input(source: .appResume, reason: reason(.timeout)))

        XCTAssertEqual(first.action, .reloadPlayURL)
        XCTAssertEqual(duplicate.action, .ignore(.duplicateFailure))
    }

    @MainActor
    func testNetworkFailureReloadsSameVariantBeforeFallingBack() {
        var coordinator = VideoDetailPlaybackRecoveryCoordinator()
        let decision = coordinator.receiveFailure(input(reason: reason(.network), hasFallbackVariant: true))

        XCTAssertEqual(decision.action, .reloadPlayURL)
        XCTAssertTrue(decision.shouldRefreshCDN)
    }

    @MainActor
    func testNetworkFailureFallsBackAfterSameVariantRetry() {
        var coordinator = VideoDetailPlaybackRecoveryCoordinator()
        _ = coordinator.receiveFailure(input(reason: reason(.network), recoveryAttemptCount: 0))

        let retry = coordinator.receiveFailure(input(reason: reason(.network), recoveryAttemptCount: 1))

        XCTAssertEqual(retry.action, .switchVariant)
    }

    @MainActor
    func testDecoderFailureSwitchesVariantWhenFallbackExists() {
        var coordinator = VideoDetailPlaybackRecoveryCoordinator()
        let decision = coordinator.receiveFailure(input(
            reason: reason(.decoderFailed, layer: .avPlayerItem),
            hasFallbackVariant: true
        ))

        XCTAssertEqual(decision.action, .switchVariant)
        XCTAssertFalse(decision.shouldRefreshCDN)
        XCTAssertTrue(decision.shouldMarkFailedVariant)
    }

    @MainActor
    func testLocalFailureDoesNotRefreshCDN() {
        var coordinator = VideoDetailPlaybackRecoveryCoordinator()
        let decision = coordinator.receiveFailure(input(
            reason: reason(.unknown, layer: .local),
            hasFallbackVariant: true
        ))

        XCTAssertEqual(decision.action, .switchVariant)
        XCTAssertFalse(decision.shouldRefreshCDN)
    }

    @MainActor
    func testNetworkFailureReloadsWhenNoFallbackExistsAndAttemptsRemain() {
        var coordinator = VideoDetailPlaybackRecoveryCoordinator()
        let decision = coordinator.receiveFailure(input(reason: reason(.network), hasFallbackVariant: false))

        XCTAssertEqual(decision.action, .reloadPlayURL)
    }

    @MainActor
    func testReloadExhaustsWhenNoFallbackAndAttemptLimitReached() {
        var coordinator = VideoDetailPlaybackRecoveryCoordinator()
        let decision = coordinator.receiveFailure(input(
            reason: reason(.network),
            hasFallbackVariant: false,
            recoveryAttemptCount: 2
        ))

        XCTAssertEqual(decision.action, .exhausted)
    }

    @MainActor
    func testStaleVariantIsIgnored() {
        var coordinator = VideoDetailPlaybackRecoveryCoordinator()
        let decision = coordinator.receiveFailure(input(selectedVariantID: "other-variant"))

        XCTAssertEqual(decision.action, .ignore(.staleVariant))
    }

    private func input(
        source: VideoDetailPlaybackRecoveryFailureSource = .playerCallback,
        message: String = "播放失败",
        reason: HLSBridgeFailureReason? = nil,
        selectedVariantID: String? = "failed-variant",
        hasFallbackVariant: Bool = true,
        playURLIsLoading: Bool = false,
        recoveryAttemptCount: Int = 0,
        isPlaybackInvalidatedForNavigation: Bool = false,
        hasPendingNavigationInterruption: Bool = false
    ) -> VideoDetailPlaybackRecoveryInput {
        VideoDetailPlaybackRecoveryInput(
            source: source,
            message: message,
            reason: reason,
            failedVariantID: "failed-variant",
            selectedVariantID: selectedVariantID,
            hasFallbackVariant: hasFallbackVariant,
            playURLIsLoading: playURLIsLoading,
            recoveryAttemptCount: recoveryAttemptCount,
            maxRecoveryReloadAttempts: 2,
            isPlaybackInvalidatedForNavigation: isPlaybackInvalidatedForNavigation,
            hasPendingNavigationInterruption: hasPendingNavigationInterruption
        )
    }

    private func reason(
        _ category: HLSBridgeRemoteFailureCategory,
        statusCode: Int? = nil,
        layer: HLSBridgeFailureReason.Layer = .remoteRange
    ) -> HLSBridgeFailureReason {
        HLSBridgeFailureReason(
            layer: layer,
            category: category,
            statusCode: statusCode,
            urlHost: "upos.example.test",
            rangeDescription: nil,
            underlyingDescription: nil
        )
    }
}

final class VideoDetailPlaybackQualityMenuBuilderTests: XCTestCase {
    @MainActor
    func testQualityMenuAllowsAdvertisedQualityToLoadOnDemand() {
        let onDemandVariant = PlayVariant(
            quality: 112,
            title: "1080P 高码率",
            videoURL: nil,
            audioURL: nil,
            videoStream: nil,
            audioStream: nil,
            codec: "HEVC",
            resolution: nil,
            frameRate: nil,
            bandwidth: nil,
            isHDR: false,
            badge: nil,
            isAvailabilityPending: true
        )

        let item = VideoDetailPlaybackQualityMenuBuilder.makeQualityMenuItems(
            playVariants: [onDemandVariant],
            selectedPlayVariant: nil,
            pendingPlayVariantID: nil,
            isSwitchingPlayQuality: false
        ).first

        XCTAssertEqual(item?.systemImage, "arrow.down.circle")
        XCTAssertEqual(item?.subtitle, "HEVC · DASH")
        XCTAssertFalse(item?.isDisabled ?? true)
    }

    @MainActor
    func testQualityMenuSubtitleShowsProgressiveFallbackRoute() throws {
        let originalVariant = try dashVariant(
            stream: stream(id: 64, codecs: "hev1.1.6.L120.90", codecid: 12)
        )
        let fallbackVariant = PlayVariant(
            quality: 64,
            title: "720P 准高清",
            videoURL: try XCTUnwrap(URL(string: "https://example.test/video-progressive.mp4")),
            audioURL: nil,
            videoStream: nil,
            audioStream: nil,
            codec: "mp4",
            resolution: "1280x720",
            frameRate: "30",
            bandwidth: 520_000,
            isHDR: false,
            badge: nil
        )

        let item = VideoDetailPlaybackQualityMenuBuilder.makeQualityMenuItems(
            playVariants: [originalVariant],
            selectedPlayVariant: fallbackVariant,
            pendingPlayVariantID: nil,
            isSwitchingPlayQuality: false
        ).first

        XCTAssertEqual(item?.systemImage, "checkmark")
        XCTAssertEqual(item?.subtitle, "单流兜底")
    }

    @MainActor
    func testQualityMenuSubtitleShowsH264CodecFallbackRoute() throws {
        let originalVariant = try dashVariant(
            stream: stream(id: 116, codecs: "hev1.1.6.L150.90", codecid: 12)
        )
        let fallbackVariant = try dashVariant(
            stream: stream(
                id: 116,
                codecs: "avc1.640028",
                codecid: 7,
                baseURL: "https://example.test/video-h264.m4s"
            )
        )

        let item = VideoDetailPlaybackQualityMenuBuilder.makeQualityMenuItems(
            playVariants: [originalVariant],
            selectedPlayVariant: fallbackVariant,
            pendingPlayVariantID: nil,
            isSwitchingPlayQuality: false
        ).first

        XCTAssertEqual(item?.systemImage, "checkmark")
        XCTAssertEqual(item?.subtitle, "H.264 兜底")
    }

    private func dashVariant(stream videoStream: DASHStream) throws -> PlayVariant {
        let audioStream = try stream(
            id: 30280,
            codecs: "mp4a.40.2",
            codecid: 0,
            baseURL: "https://example.test/audio.m4s"
        )
        return PlayVariant(
            quality: videoStream.id ?? 64,
            title: BiliVideoQuality.title(for: videoStream.id ?? 64),
            videoURL: videoStream.playURL,
            audioURL: audioStream.playURL,
            videoStream: videoStream,
            audioStream: audioStream,
            codec: videoStream.codecLabel,
            resolution: videoStream.resolutionLabel,
            frameRate: videoStream.frameRate,
            bandwidth: videoStream.bandwidth,
            isHDR: false,
            badge: nil
        )
    }

    private func stream(
        id: Int,
        codecs: String,
        codecid: Int,
        baseURL: String = "https://example.test/video.m4s"
    ) throws -> DASHStream {
        let json = """
        {
          "id": \(id),
          "baseUrl": "\(baseURL)",
          "bandwidth": 1000000,
          "codecs": "\(codecs)",
          "codecid": \(codecid),
          "width": 1280,
          "height": 720,
          "frameRate": "30",
          "mimeType": "video/mp4"
        }
        """
        return try JSONDecoder().decode(DASHStream.self, from: Data(json.utf8))
    }
}
