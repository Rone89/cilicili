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
        let title = app.staticTexts["search.feed.title"]
        XCTAssertTrue(title.exists, app.debugDescription)
        XCTAssertEqual(title.label, "搜索")

        let searchButton = app.buttons["search.top.button"]
        XCTAssertTrue(searchButton.exists, app.debugDescription)
        XCTAssertTrue(searchButton.isHittable, app.debugDescription)

        let filterMenu = app.buttons["search.filters.menu"]
        XCTAssertTrue(filterMenu.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertGreaterThan(searchButton.frame.minX, title.frame.maxX)
        XCTAssertGreaterThan(filterMenu.frame.minX, searchButton.frame.midX)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "search-toolbar-idle"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testSearchButtonSplitsSortMenuClearKeepsFieldAndEmptyBlurCollapses() {
        let app = launchFixture()
        let searchButton = app.buttons["search.top.button"]
        let hittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == true"),
            object: searchButton
        )
        XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: 5), .completed, app.debugDescription)
        searchButton.tap()

        let field = app.textFields["search.top.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        let filterMenu = app.buttons["search.filters.menu"]
        XCTAssertTrue(filterMenu.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertGreaterThan(filterMenu.frame.minX, field.frame.maxX)
        XCTAssertFalse(app.buttons["search.top.cancel"].exists)

        let expandedShot = XCTAttachment(screenshot: app.screenshot())
        expandedShot.name = "search-toolbar-expanded-sort"
        expandedShot.lifetime = .keepAlways
        add(expandedShot)

        filterMenu.tap()
        XCTAssertTrue(app.staticTexts["排序方式"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["最多播放"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 3), app.debugDescription)

        field.tap()
        field.typeText("测试")
        XCTAssertEqual(field.value as? String, "测试")

        let clearButton = app.buttons["search.top.clear"]
        XCTAssertTrue(clearButton.waitForExistence(timeout: 3), app.debugDescription)
        clearButton.tap()
        XCTAssertTrue(field.exists, app.debugDescription)
        XCTAssertFalse(app.buttons["search.top.button"].exists)

        field.typeText("\n")
        XCTAssertTrue(app.buttons["search.top.button"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.textFields["search.top.field"].exists)
    }

    func testSettingsButtonOpensSortMenu() {
        let app = launchFixture()
        app.buttons["search.filters.menu"].tap()
        XCTAssertTrue(app.staticTexts["排序方式"].waitForExistence(timeout: 5), app.debugDescription)
    }

    func testHiddenSearchPageKeepsSwitcherAndMorphsSearchBar() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-cc.bili.display.visibleRootTabs.v1", "(home,dynamic)",
            "--ui-test-enable-animations"
        ]
        app.launch()
        addTeardownBlock { app.terminate() }

        let modeMenu = app.buttons["home.feed.modeMenu"]
        XCTAssertTrue(modeMenu.waitForExistence(timeout: 15), app.debugDescription)
        modeMenu.tap()
        let searchMenuItem = app.buttons["搜索"]
        XCTAssertTrue(searchMenuItem.waitForExistence(timeout: 5), app.debugDescription)
        searchMenuItem.tap()

        let searchButton = app.buttons["search.top.button"]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 10), app.debugDescription)
        let switcher = app.buttons["root.hiddenPageSwitcher"]
        XCTAssertTrue(switcher.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertGreaterThan(switcher.frame.minX, searchButton.frame.maxX)

        searchButton.tap()
        let field = app.textFields["search.top.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        let expandedFilter = app.buttons["search.filters.menu"]
        XCTAssertTrue(expandedFilter.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertGreaterThan(expandedFilter.frame.minX, field.frame.maxX)
        XCTAssertFalse(switcher.exists)

        let hiddenExpandedShot = XCTAttachment(screenshot: app.screenshot())
        hiddenExpandedShot.name = "search-roottab-expanded-sort"
        hiddenExpandedShot.lifetime = .keepAlways
        add(hiddenExpandedShot)

        field.tap()
        field.typeText("\n")
        XCTAssertTrue(searchButton.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(switcher.waitForExistence(timeout: 5), app.debugDescription)

        switcher.tap()
        let homeItem = app.collectionViews.buttons["首页"]
        XCTAssertTrue(homeItem.waitForExistence(timeout: 5), app.debugDescription)
        homeItem.tap()
        XCTAssertTrue(modeMenu.waitForExistence(timeout: 5), app.debugDescription)
    }
}
