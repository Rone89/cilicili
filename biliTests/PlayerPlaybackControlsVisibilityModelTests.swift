import XCTest
@testable import bili

final class PlayerPlaybackControlsVisibilityModelTests: XCTestCase {
    @MainActor
    func testDefaultAutoHideStillRemovesControls() async throws {
        let model = PlayerPlaybackControlsVisibilityModel()
        model.scheduleAutoHide(showsPlaybackControls: true, isLayoutTransitioning: false)

        let deadline = ContinuousClock.now + .seconds(6)
        while model.isVisible, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }

        XCTAssertFalse(model.isVisible)
        XCTAssertEqual(model.opacity, 0)
        XCTAssertFalse(model.acceptsHitTesting)
    }

    @MainActor
    func testImmediateHideRemovesControlsWithoutTransitionDelay() {
        let model = PlayerPlaybackControlsVisibilityModel()

        model.hide(animated: false)

        XCTAssertFalse(model.isVisible)
        XCTAssertEqual(model.opacity, 0)
        XCTAssertFalse(model.acceptsHitTesting)
    }

    @MainActor
    func testAnimatedHideStopsHitTestingBeforeTheFadeCompletes() async throws {
        let model = PlayerPlaybackControlsVisibilityModel()

        model.hide(animated: true)

        XCTAssertTrue(model.isVisible)
        XCTAssertEqual(model.opacity, 0)
        XCTAssertFalse(model.acceptsHitTesting)

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
