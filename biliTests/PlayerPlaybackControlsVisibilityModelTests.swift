import XCTest
@testable import bili

final class PlayerPlaybackControlsVisibilityModelTests: XCTestCase {
    @MainActor
    func testImmediateHideRemovesControlsWithoutTransitionDelay() {
        let model = PlayerPlaybackControlsVisibilityModel()

        model.hide(animated: false)

        XCTAssertFalse(model.isVisible)
        XCTAssertEqual(model.opacity, 0)
        XCTAssertFalse(model.acceptsHitTesting)
    }

    @MainActor
    func testAnimatedHideKeepsControlsTouchableDuringFade() async throws {
        let model = PlayerPlaybackControlsVisibilityModel()

        model.hide(animated: true)

        XCTAssertTrue(model.isVisible)
        XCTAssertEqual(model.opacity, 0)
        XCTAssertTrue(model.acceptsHitTesting)

        for _ in 0..<12 where model.isVisible {
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        XCTAssertFalse(model.isVisible)
        XCTAssertFalse(model.acceptsHitTesting)
    }

    @MainActor
    func testShowCancelsPendingAnimatedHideRemoval() async throws {
        let model = PlayerPlaybackControlsVisibilityModel()

        model.hide(animated: true)
        model.show(
            scheduleAutoHide: false,
            animated: false,
            showsPlaybackControls: true
        )

        try await Task.sleep(nanoseconds: 420_000_000)

        XCTAssertTrue(model.isVisible)
        XCTAssertEqual(model.opacity, 1)
        XCTAssertTrue(model.acceptsHitTesting)
    }
}
