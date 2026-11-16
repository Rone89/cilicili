import XCTest
@testable import bili

final class FeedChromeTitleStateTests: XCTestCase {
    private let restingInset: CGFloat = 118

    func testProgressClampsAtFadeDistance() {
        XCTAssertEqual(FeedChromeTitleState.progress(forContentOffsetY: -12), 0)
        XCTAssertEqual(FeedChromeTitleState.progress(forContentOffsetY: 0), 0)
        XCTAssertEqual(
            FeedChromeTitleState.progress(forContentOffsetY: FeedChromeTitleState.fadeDistance / 2),
            0.5,
            accuracy: 0.0001
        )
        XCTAssertEqual(FeedChromeTitleState.progress(forContentOffsetY: FeedChromeTitleState.fadeDistance), 1)
        XCTAssertEqual(FeedChromeTitleState.progress(forContentOffsetY: 400), 1)
    }

    func testStateIgnoresNegativeOffsetsAndSmallDeltas() {
        let state = FeedChromeTitleState()

        state.update(scrollSum: -40, insetsTop: restingInset)
        XCTAssertEqual(state.progress, 0)

        state.update(scrollSum: FeedChromeTitleState.fadeDistance / 2, insetsTop: restingInset)
        XCTAssertEqual(state.progress, 0.5, accuracy: 0.0001)

        state.update(scrollSum: FeedChromeTitleState.fadeDistance / 2 + 0.05, insetsTop: restingInset)
        XCTAssertEqual(state.progress, 0.5, accuracy: 0.0001)
    }

    func testResetRestoresVisibleTitle() {
        let state = FeedChromeTitleState()
        state.update(scrollSum: FeedChromeTitleState.fadeDistance, insetsTop: restingInset)
        XCTAssertEqual(state.progress, 1)

        state.reset()
        XCTAssertEqual(state.progress, 0)
    }

    func testRefreshInsetInflationFreezesTitleVisible() {
        let state = FeedChromeTitleState()
        // Establish the resting inset.
        state.update(scrollSum: 0, insetsTop: restingInset)

        // Pull-to-refresh inflates the top inset while the raw offset has not
        // compensated, so the sum reads as a downward scroll. The title must
        // stay visible instead of flickering out.
        state.update(scrollSum: 60, insetsTop: restingInset + 60)
        XCTAssertEqual(state.progress, 0)
        state.update(scrollSum: 16, insetsTop: restingInset + 60)
        XCTAssertEqual(state.progress, 0)

        // Once the inset settles back, normal scroll-driven fading resumes.
        state.update(scrollSum: 0, insetsTop: restingInset)
        state.update(scrollSum: FeedChromeTitleState.fadeDistance, insetsTop: restingInset)
        XCTAssertEqual(state.progress, 1)
    }

    func testExplicitRefreshFlagAlsoFreezesTitle() {
        let state = FeedChromeTitleState()
        state.update(scrollSum: 0, insetsTop: restingInset)
        state.update(scrollSum: FeedChromeTitleState.fadeDistance, insetsTop: restingInset)
        XCTAssertEqual(state.progress, 1)

        state.update(scrollSum: 400, insetsTop: restingInset, isRefreshing: true)
        XCTAssertEqual(state.progress, 0)
    }
}
