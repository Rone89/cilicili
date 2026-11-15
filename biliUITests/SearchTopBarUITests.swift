import XCTest

@MainActor
final class SearchTopBarUITests: XCTestCase {
    private func launchFixture() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "searchTopBar"]
        app.launch()
        XCTAssertTrue(app.buttons["search.top.button"].waitForExistence(timeout: 20), app.debugDescription)
        addTeardownBlock { app.terminate() }
        return app
    }

    func testTitleAndGlassButtonsPresent() {
        let app = launchFixture()
        XCTAssertTrue(app.staticTexts["search.feed.title"].exists)
        XCTAssertEqual(app.staticTexts["search.feed.title"].label, "搜索")
        // The search button and the settings button share one glass capsule in
        // the page-owned top bar, so they surface as plain app buttons.
        XCTAssertTrue(app.buttons["search.top.button"].exists, app.debugDescription)
        XCTAssertTrue(app.buttons["search.filters.menu"].waitForExistence(timeout: 5))
    }

    func testSearchButtonRevealsFieldAndCancelRestores() {
        let app = launchFixture()
        app.buttons["search.top.button"].tap()

        let field = app.textFields["search.top.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["search.top.cancel"].waitForExistence(timeout: 3))

        field.tap()
        field.typeText("测试")
        XCTAssertEqual(field.value as? String, "测试")

        app.buttons["search.top.cancel"].tap()
        XCTAssertTrue(app.buttons["search.top.button"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["search.top.field"].exists)
    }

    func testSettingsButtonOpensSortMenu() {
        let app = launchFixture()
        app.buttons["search.filters.menu"].tap()
        XCTAssertTrue(app.staticTexts["排序方式"].waitForExistence(timeout: 5), app.debugDescription)
    }
}
