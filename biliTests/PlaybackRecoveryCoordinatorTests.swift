import XCTest
@testable import bili

final class PlaybackRecoveryCoordinatorTests: XCTestCase {
    func testAuthDeniedReloadsPlayURLWithoutCDNRefresh() {
        var coordinator = VideoDetailPlaybackRecoveryCoordinator()
        let decision = coordinator.receiveFailure(input(reason: reason(.authDenied, statusCode: 403)))

        XCTAssertEqual(decision.action, .reloadPlayURL)
        XCTAssertTrue(decision.shouldHandleFailure)
        XCTAssertTrue(decision.shouldMarkFailedVariant)
        XCTAssertFalse(decision.shouldRefreshCDN)
    }

    func testRateLimitedReloadsPlayURLAndRefreshesCDN() {
        var coordinator = VideoDetailPlaybackRecoveryCoordinator()
        let decision = coordinator.receiveFailure(input(reason: reason(.rateLimited, statusCode: 429)))

        XCTAssertEqual(decision.action, .reloadPlayURL)
        XCTAssertTrue(decision.shouldRefreshCDN)
    }

    func testCancelledFailureIsIgnored() {
        var coordinator = VideoDetailPlaybackRecoveryCoordinator()
        let decision = coordinator.receiveFailure(input(reason: reason(.cancelled)))

        XCTAssertEqual(decision.action, .ignore(.cancelled))
        XCTAssertFalse(decision.shouldHandleFailure)
        XCTAssertFalse(decision.shouldMarkFailedVariant)
    }

    func testDuplicateFailureIsIgnoredAcrossSources() {
        var coordinator = VideoDetailPlaybackRecoveryCoordinator()
        let first = coordinator.receiveFailure(input(source: .playerCallback, reason: reason(.timeout)))
        let duplicate = coordinator.receiveFailure(input(source: .appResume, reason: reason(.timeout)))

        XCTAssertEqual(first.action, .switchVariant)
        XCTAssertEqual(duplicate.action, .ignore(.duplicateFailure))
    }

    func testNetworkFailureSwitchesVariantWhenFallbackExists() {
        var coordinator = VideoDetailPlaybackRecoveryCoordinator()
        let decision = coordinator.receiveFailure(input(reason: reason(.network), hasFallbackVariant: true))

        XCTAssertEqual(decision.action, .switchVariant)
        XCTAssertTrue(decision.shouldRefreshCDN)
    }

    func testNetworkFailureReloadsWhenNoFallbackExistsAndAttemptsRemain() {
        var coordinator = VideoDetailPlaybackRecoveryCoordinator()
        let decision = coordinator.receiveFailure(input(reason: reason(.network), hasFallbackVariant: false))

        XCTAssertEqual(decision.action, .reloadPlayURL)
    }

    func testReloadExhaustsWhenNoFallbackAndAttemptLimitReached() {
        var coordinator = VideoDetailPlaybackRecoveryCoordinator()
        let decision = coordinator.receiveFailure(input(
            reason: reason(.network),
            hasFallbackVariant: false,
            recoveryAttemptCount: 2
        ))

        XCTAssertEqual(decision.action, .exhausted)
    }

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
        statusCode: Int? = nil
    ) -> HLSBridgeFailureReason {
        HLSBridgeFailureReason(
            layer: .remoteRange,
            category: category,
            statusCode: statusCode,
            urlHost: "upos.example.test",
            rangeDescription: nil,
            underlyingDescription: nil
        )
    }
}
