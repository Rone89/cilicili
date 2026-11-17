import XCTest

@MainActor
final class SearchTopBarUITests: XCTestCase {
    private func nativeSearchButton(in app: XCUIApplication) -> XCUIElement {
        app.navigationBars.buttons.matching(
            NSPredicate(format: "label IN %@ OR identifier == %@", ["Search", "搜索"], "search.top.button")
        ).firstMatch
    }

    private func nativeSearchField(in app: XCUIApplication) -> XCUIElement {
        app.searchFields.firstMatch
    }

    private func nativeCloseSearchButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "label IN %@ OR identifier == %@", ["close", "Close", "Cancel", "Dismiss", "关闭", "取消"], "search.top.cancel")
        ).firstMatch
    }

    private func launchFixture() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "searchTopBar"]
        app.launch()
        XCTAssertTrue(nativeSearchButton(in: app).waitForExistence(timeout: 20), app.debugDescription)
        addTeardownBlock { app.terminate() }
        return app
    }

    func testTitleAndGlassButtonsPresent() {
        let app = launchFixture()
        let title = app.staticTexts["search.feed.title"]
        XCTAssertTrue(title.exists, app.debugDescription)
        XCTAssertEqual(title.label, "搜索")

        let searchButton = nativeSearchButton(in: app)
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

    func testSearchButtonMorphsFieldClearKeepsFieldAndCloseRestoresToolbar() {
        let app = launchFixture()
        let searchButton = nativeSearchButton(in: app)
        let hittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == true"),
            object: searchButton
        )
        XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: 5), .completed, app.debugDescription)
        searchButton.tap()

        let field = nativeSearchField(in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        let closeButton = nativeCloseSearchButton(in: app)
        XCTAssertTrue(closeButton.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertGreaterThan(closeButton.frame.minX, field.frame.maxX)

        XCTAssertFalse(searchButton.exists, app.debugDescription)
        let filterMenu = app.buttons["search.filters.menu"]
        XCTAssertFalse(filterMenu.exists, app.debugDescription)

        let expandedShot = XCTAttachment(screenshot: app.screenshot())
        expandedShot.name = "search-toolbar-expanded-sort"
        expandedShot.lifetime = .keepAlways
        add(expandedShot)

        field.tap()
        field.typeText("测试")
        XCTAssertEqual(field.value as? String, "测试")

        let clearButton = field.buttons.firstMatch
        XCTAssertTrue(clearButton.waitForExistence(timeout: 3), app.debugDescription)
        clearButton.tap()
        XCTAssertTrue(field.exists, app.debugDescription)
        XCTAssertFalse(searchButton.exists)

        closeButton.tap()
        XCTAssertTrue(searchButton.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(filterMenu.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(nativeSearchField(in: app).exists)
    }

    func testSettingsButtonOpensSortMenu() {
        let app = launchFixture()
        let filterMenu = app.buttons["search.filters.menu"]
        filterMenu.tap()
        XCTAssertTrue(app.staticTexts["排序方式"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["最多播放"].tap()
        XCTAssertEqual(filterMenu.value as? String, "最多播放", app.debugDescription)
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

        let searchButton = nativeSearchButton(in: app)
        XCTAssertTrue(searchButton.waitForExistence(timeout: 10), app.debugDescription)
        let switcher = app.buttons["root.hiddenPageSwitcher"]
        XCTAssertTrue(switcher.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertGreaterThan(switcher.frame.minX, searchButton.frame.maxX)
        XCTAssertLessThan(switcher.frame.width, 80)

        searchButton.tap()
        let field = nativeSearchField(in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        let closeButton = nativeCloseSearchButton(in: app)
        XCTAssertTrue(closeButton.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertGreaterThan(closeButton.frame.minX, field.frame.maxX)

        let hiddenExpandedShot = XCTAttachment(screenshot: app.screenshot())
        hiddenExpandedShot.name = "search-roottab-expanded-sort"
        hiddenExpandedShot.lifetime = .keepAlways
        add(hiddenExpandedShot)

        closeButton.tap()
        XCTAssertTrue(searchButton.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(switcher.waitForExistence(timeout: 5), app.debugDescription)

        switcher.tap()
        let homeItem = app.collectionViews.buttons["首页"]
        XCTAssertTrue(homeItem.waitForExistence(timeout: 5), app.debugDescription)
        homeItem.tap()
        XCTAssertTrue(modeMenu.waitForExistence(timeout: 5), app.debugDescription)
    }
}
