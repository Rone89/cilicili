import XCTest
@testable import bili

final class PlaybackCDNStickyRecommendationTests: XCTestCase {
    @MainActor
    func testWeakProbeDoesNotReplaceVerifiedRecommendation() {
        let previous = snapshot(recommended: .ali, results: [result(.ali, elapsed: 180)])
        let weakProbe = snapshot(
            recommended: nil,
            results: [result(.cos, elapsed: 90, mode: .bareHostFallback, isWeak: true)]
        )

        let stabilized = weakProbe.stabilizedRecommendation(previous: previous)
        XCTAssertEqual(stabilized.recommendedPreference, .ali)
        XCTAssertEqual(stabilized.probedAt, weakProbe.probedAt)
        XCTAssertTrue(stabilized.result(for: .ali)?.isActionableForPlaybackRecommendation == true)
    }

    @MainActor
    func testSmallLatencyAdvantageKeepsCurrentRecommendation() {
        let previous = snapshot(recommended: .ali, results: [result(.ali, elapsed: 220)])
        let refreshed = snapshot(
            recommended: .cos,
            results: [result(.cos, elapsed: 170), result(.ali, elapsed: 220)]
        )

        XCTAssertEqual(
            refreshed.stabilizedRecommendation(previous: previous).recommendedPreference,
            .ali
        )
    }

    @MainActor
    func testMaterialLatencyAdvantageSwitchesRecommendation() {
        let previous = snapshot(recommended: .ali, results: [result(.ali, elapsed: 400)])
        let refreshed = snapshot(
            recommended: .cos,
            results: [result(.cos, elapsed: 220), result(.ali, elapsed: 400)]
        )

        XCTAssertEqual(
            refreshed.stabilizedRecommendation(previous: previous).recommendedPreference,
            .cos
        )
    }

    @MainActor
    func testCurrentFailureSwitchesRecommendation() {
        let previous = snapshot(recommended: .ali, results: [result(.ali, elapsed: 180)])
        let refreshed = snapshot(
            recommended: .cos,
            results: [
                result(.cos, elapsed: 210),
                result(.ali, elapsed: 180, succeeded: false)
            ]
        )

        XCTAssertEqual(
            refreshed.stabilizedRecommendation(previous: previous).recommendedPreference,
            .cos
        )
    }

    @MainActor
    func testPlaybackDegradationDisablesHysteresis() {
        let previous = snapshot(recommended: .ali, results: [result(.ali, elapsed: 220)])
        let refreshed = snapshot(
            recommended: .cos,
            results: [result(.cos, elapsed: 190), result(.ali, elapsed: 220)]
        )

        XCTAssertEqual(
            refreshed.stabilizedRecommendation(
                previous: previous,
                keepsCurrentRecommendation: false
            ).recommendedPreference,
            .cos
        )
    }

    @MainActor
    func testUnsafeRewriteDoesNotReplaceVerifiedRecommendation() {
        let previous = snapshot(recommended: .ali, results: [result(.ali, elapsed: 220)])
        let refreshed = snapshot(
            recommended: .cos,
            results: [
                result(.cos, elapsed: 160),
                PlaybackCDNProbeResult(
                    preference: .ali,
                    elapsedMilliseconds: nil,
                    didSucceed: false,
                    errorDescription: "unsafe",
                    probeMode: .realPlaybackURL,
                    isCandidateCompatible: false
                )
            ]
        )

        let stabilized = refreshed.stabilizedRecommendation(previous: previous)
        XCTAssertEqual(stabilized.recommendedPreference, .ali)
        XCTAssertEqual(stabilized.probedAt, refreshed.probedAt)
        XCTAssertTrue(stabilized.result(for: .ali)?.isActionableForPlaybackRecommendation == true)
    }

    @MainActor
    private func snapshot(
        recommended: PlaybackCDNPreference?,
        results: [PlaybackCDNProbeResult]
    ) -> PlaybackCDNProbeSnapshot {
        PlaybackCDNProbeSnapshot(
            probedAt: Date(timeIntervalSince1970: 1_000),
            recommendedPreference: recommended,
            results: results
        )
    }

    @MainActor
    private func result(
        _ preference: PlaybackCDNPreference,
        elapsed: Int,
        succeeded: Bool = true,
        mode: PlaybackCDNProbeMode = .realPlaybackURL,
        isWeak: Bool = false
    ) -> PlaybackCDNProbeResult {
        PlaybackCDNProbeResult(
            preference: preference,
            elapsedMilliseconds: elapsed,
            didSucceed: succeeded,
            errorDescription: succeeded ? nil : "failed",
            probeMode: mode,
            isWeakReference: isWeak
        )
    }
}
