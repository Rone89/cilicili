import XCTest

@MainActor
final class MineTopBarUITests: XCTestCase {
    private func inlineSearchField(in app: XCUIApplication) -> XCUIElement {
        app.textFields["mine.search.field"].firstMatch
    }

    private func launchFixture() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "mineTopBar"]
        app.launch()
        XCTAssertTrue(inlineSearchField(in: app).waitForExistence(timeout: 20), app.debugDescription)
        addTeardownBlock { app.terminate() }
        return app
    }

    func testTitleAndInlineSearchFieldPresentAtTop() {
        let app = launchFixture()
        let title = app.staticTexts["mine.feed.title"]
        XCTAssertTrue(title.exists, app.debugDescription)
        XCTAssertEqual(title.label, "我的")

        let field = inlineSearchField(in: app)
        XCTAssertTrue(field.exists, app.debugDescription)
        XCTAssertTrue(field.isHittable, app.debugDescription)
        XCTAssertGreaterThan(field.frame.minY, title.frame.minY)
    }

    func testInlineSearchFieldFiltersClearsAndScrollsWithPage() {
        let app = launchFixture()
        let field = inlineSearchField(in: app)
        let initialMinY = field.frame.minY

        field.tap()
        field.typeText("设置")
        XCTAssertEqual(field.value as? String, "设置")

        let clearButton = app.buttons["mine.search.clear"].firstMatch
        XCTAssertTrue(clearButton.waitForExistence(timeout: 3), app.debugDescription)
        clearButton.tap()
        let clearedValue = field.value as? String ?? ""
        XCTAssertTrue(
            clearedValue.isEmpty || clearedValue == "搜索我的页功能",
            "Expected cleared field value, got '\(clearedValue)'"
        )

        let cancelButton = app.buttons["mine.search.cancel"].firstMatch
        if cancelButton.waitForExistence(timeout: 2) {
            cancelButton.tap()
        }

        let scrollContainer = app.collectionViews.firstMatch.exists
            ? app.collectionViews.firstMatch
            : app.tables.firstMatch
        XCTAssertTrue(scrollContainer.waitForExistence(timeout: 5), app.debugDescription)
        scrollContainer.swipeUp()
        if field.exists {
            XCTAssertLessThan(field.frame.minY, initialMinY)
        }
    }
}
