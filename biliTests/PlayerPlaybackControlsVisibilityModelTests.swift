import XCTest
@testable import bili

final class PlayerPlaybackControlsVisibilityModelTests: XCTestCase {
    @MainActor
    func testAnimatedHideKeepsControlsTouchableDuringFade() async throws {
        let model = PlayerPlaybackControlsVisibilityModel()

        model.hide(animated: true)

        XCTAssertTrue(model.isVisible)
        XCTAssertEqual(model.opacity, 0)
        XCTAssertTrue(model.acceptsHitTesting)

        try await Task.sleep(nanoseconds: 420_000_000)

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
