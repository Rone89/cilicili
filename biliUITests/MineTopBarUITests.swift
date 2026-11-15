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
        // The mine bar is page-owned (safe-area inset), so the button surfaces
        // as a plain app button, not a navigation-bar button.
        XCTAssertTrue(app.buttons["mine.search.button"].exists, app.debugDescription)
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
