import XCTest

@testable import bili

@MainActor
final class ScrollMinimizingTabBarProgressTests: XCTestCase {
    func testProgressIgnoresShortContentAndTracksScrollableContent() {
        var progress = ScrollMinimizingTabBarProgress()

        XCTAssertEqual(
            progress.update(offset: 100, contentHeight: 500, containerHeight: 500),
            0
        )

        XCTAssertEqual(
            progress.update(offset: 1, contentHeight: 1_000, containerHeight: 500),
            0
        )
        XCTAssertEqual(
            progress.update(offset: 85, contentHeight: 1_000, containerHeight: 500),
            1,
            accuracy: 0.001
        )
    }

    func testDirectionChangeKeepsProgressContinuous() {
        var progress = ScrollMinimizingTabBarProgress()

        _ = progress.update(offset: 1, contentHeight: 1_000, containerHeight: 500)
        XCTAssertEqual(
            progress.update(offset: 85, contentHeight: 1_000, containerHeight: 500),
            1,
            accuracy: 0.001
        )
        XCTAssertEqual(
            progress.update(offset: 70, contentHeight: 1_000, containerHeight: 500),
            1,
            accuracy: 0.001
        )
        XCTAssertEqual(
            progress.update(offset: 28, contentHeight: 1_000, containerHeight: 500),
            0.5,
            accuracy: 0.001
        )
    }

    func testFastScrollSettlesInLastScrollDirection() {
        var progress = ScrollMinimizingTabBarProgress()

        _ = progress.update(offset: 1, contentHeight: 1_000, containerHeight: 500)
        _ = progress.update(offset: 10, contentHeight: 1_000, containerHeight: 500)
        XCTAssertEqual(progress.settle(), 1)

        _ = progress.update(offset: 1, contentHeight: 1_000, containerHeight: 500)
        XCTAssertEqual(progress.settle(), 0)
    }
}
