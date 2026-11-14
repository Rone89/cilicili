import XCTest
@testable import bili

final class HomeChromeTitleStateTests: XCTestCase {
    func testProgressClampsAtFadeDistance() {
        XCTAssertEqual(HomeChromeTitleState.progress(forContentOffsetY: -12), 0)
        XCTAssertEqual(HomeChromeTitleState.progress(forContentOffsetY: 0), 0)
        XCTAssertEqual(
            HomeChromeTitleState.progress(forContentOffsetY: HomeChromeTitleState.fadeDistance / 2),
            0.5,
            accuracy: 0.0001
        )
        XCTAssertEqual(HomeChromeTitleState.progress(forContentOffsetY: HomeChromeTitleState.fadeDistance), 1)
        XCTAssertEqual(HomeChromeTitleState.progress(forContentOffsetY: 400), 1)
    }

    func testStateIgnoresNegativeOffsetsAndSmallDeltas() {
        let state = HomeChromeTitleState()

        state.update(contentOffsetY: -40)
        XCTAssertEqual(state.progress, 0)

        state.update(contentOffsetY: HomeChromeTitleState.fadeDistance / 2)
        XCTAssertEqual(state.progress, 0.5, accuracy: 0.0001)

        state.update(contentOffsetY: HomeChromeTitleState.fadeDistance / 2 + 0.05)
        XCTAssertEqual(state.progress, 0.5, accuracy: 0.0001)
    }

    func testResetRestoresVisibleTitle() {
        let state = HomeChromeTitleState()
        state.update(contentOffsetY: HomeChromeTitleState.fadeDistance)
        XCTAssertEqual(state.progress, 1)

        state.reset()
        XCTAssertEqual(state.progress, 0)
    }
}
