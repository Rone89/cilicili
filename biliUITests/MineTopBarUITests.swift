import XCTest

@MainActor
final class MineTopBarUITests: XCTestCase {
    private func launchFixture() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "mineTopBar"]
        app.launch()
        XCTAssertTrue(app.buttons["mine.search.button"].waitForExistence(timeout: 20), app.debugDescription)
        addTeardownBlock { app.terminate() }
        return app
    }

    func testTitleAndGlassSearchButtonPresent() {
        let app = launchFixture()
        XCTAssertTrue(app.staticTexts["mine.feed.title"].exists)
        XCTAssertEqual(app.staticTexts["mine.feed.title"].label, "我的")
        XCTAssertTrue(app.buttons["mine.search.button"].exists)
        // Root Mine hides the native navigation bar in favor of the page bar.
        XCTAssertEqual(app.navigationBars.count, 0, app.debugDescription)
    }

    func testSearchButtonRevealsFieldFiltersAndCancelRestores() {
        let app = launchFixture()
        app.buttons["mine.search.button"].tap()

        let field = app.textFields["mine.search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["mine.search.cancel"].waitForExistence(timeout: 3))

        field.typeText("设置")
        XCTAssertEqual(field.value as? String, "设置")

        app.buttons["mine.search.cancel"].tap()
        XCTAssertTrue(app.buttons["mine.search.button"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["mine.search.field"].exists)
    }
}
