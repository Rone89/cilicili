import XCTest

@MainActor
final class SearchScrollRetentionUITests: XCTestCase {
    func testReturningFromDetailKeepsVisibleResultAndOffset() {
        let app = launchFixture()
        let scrollView = app.scrollViews.firstMatch
        scrollView.swipeUp()
        scrollView.swipeUp()
        let result = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "结果 "))
            .allElementsBoundByIndex.first { element in
                element.isHittable && element.frame.minY > 200 && element.frame.maxY < 650
            }
        guard let result else { return XCTFail("No scrolled result available") }
        let label = result.label
        let before = result.frame
        XCTAssertNotEqual(label, "结果 1")
        for _ in 0..<3 {
            app.staticTexts[label].tap()
            XCTAssertTrue(app.staticTexts["fixture.search.detail"].waitForExistence(timeout: 3))
            app.buttons["fixture.search.back"].tap()
            let returned = app.staticTexts[label]
            XCTAssertTrue(returned.waitForExistence(timeout: 3))
            XCTAssertTrue(returned.isHittable, "Previously visible result should remain on screen")
            XCTAssertEqual(returned.frame.minY, before.minY, accuracy: 8)
        }
    }

    func testNewSearchDoesNotRestoreOldResultsOffset() {
        let app = launchFixture()
        app.scrollViews.firstMatch.swipeUp()
        app.scrollViews.firstMatch.swipeUp()
        app.buttons["fixture.search.newQuery"].tap()
        let first = app.staticTexts["新结果 1"]
        XCTAssertTrue(first.waitForExistence(timeout: 3))
        XCTAssertTrue(first.isHittable)
    }

    private func launchFixture() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "searchScroll", "--ui-test-enable-animations"]
        app.launch()
        XCTAssertTrue(app.staticTexts["结果 1"].waitForExistence(timeout: 5))
        addTeardownBlock { app.terminate() }
        return app
    }
}
