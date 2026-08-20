import XCTest
@testable import bili

final class PlayerHorizontalSeekSensitivityTests: XCTestCase {
    @MainActor
    func testMatchesPiliPlusDefaultAcrossVideoDurations() {
        for duration in [3 * 60, 15 * 60, 2 * 60 * 60] {
            XCTAssertEqual(
                PlayerHorizontalSeekSensitivity.secondsPerFullWidth(duration: TimeInterval(duration)),
                90
            )
        }
    }

    @MainActor
    func testUsesPiliPlusDefaultWithoutDuration() {
        XCTAssertEqual(
            PlayerHorizontalSeekSensitivity.secondsPerFullWidth(duration: nil),
            90
        )
    }

    @MainActor
    func testSeekPreviewTracksSmallMovementsOnLongVideos() {
        let clock = PlayerPlaybackClock()
        clock.update(time: 3_600, duration: 7_200, force: true)
        clock.updateSeekPreview(progress: 0.5, force: true)

        clock.updateSeekPreview(progress: 0.5001)

        XCTAssertEqual(clock.seekPreviewProgress, 0.5001)
    }
}
