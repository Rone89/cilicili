import XCTest

@MainActor
final class SearchScrollRetentionUITests: XCTestCase {
    func testTapOutsideActiveSearchDismissesKeyboardAndPreservesResults() {
        let app = launchFixture()
        let search = app.textFields["navigation.search.field"]
        let originalQuery = search.value as? String
        for _ in 0..<2 {
            search.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
            XCTAssertTrue(app.buttons["navigation.search.cancel"].waitForExistence(timeout: 3))
            // The side margin is content outside a result row and the toolbar.
            app.scrollViews.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.1)).tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
            XCTAssertTrue(app.buttons["navigation.search.cancel"].waitForNonExistence(timeout: 3))
            XCTAssertEqual(search.value as? String, originalQuery)
            XCTAssertTrue(app.staticTexts["结果 1"].exists)
            XCTAssertTrue(app.tabBars.buttons["搜索"].isSelected)
        }
    }

    func testCancelAfterSubmittedSearchRestoresHotSearches() {
        let app = launchFixture()
        let search = app.textFields["navigation.search.field"]
        search.tap()
        app.buttons["navigation.search.clear"].tap()
        search.typeText("native\n")
        XCTAssertTrue(app.staticTexts["native 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))

        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        app.buttons["navigation.search.cancel"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["大家都在搜"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["热门搜索，热搜保留测试"].exists)
        XCTAssertFalse(app.staticTexts["native 1"].exists)
        XCTAssertEqual(app.textFields.matching(identifier: "navigation.search.field").count, 1)
        XCTAssertTrue(app.tabBars.buttons["搜索"].isSelected)

        app.tabBars.buttons["首页"].tap()
        app.tabBars.buttons["搜索"].tap()
        XCTAssertTrue(app.staticTexts["大家都在搜"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["热门搜索，热搜保留测试"].exists)
    }

    func testToolbarSearchSubmitCancelAndClear() {
        let app = launchFixture()
        let search = app.textFields["navigation.search.field"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        XCTAssertEqual(app.textFields.matching(identifier: "navigation.search.field").count, 1)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        let normalScreenshot = XCTAttachment(screenshot: app.screenshot())
        normalScreenshot.name = "Toolbar search resting state"
        normalScreenshot.lifetime = .keepAlways
        add(normalScreenshot)

        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        let activeScreenshot = XCTAttachment(screenshot: app.screenshot())
        activeScreenshot.name = "Toolbar search editing state"
        activeScreenshot.lifetime = .keepAlways
        add(activeScreenshot)
        app.buttons["navigation.search.clear"].tap()
        search.typeText("native\n")
        XCTAssertTrue(app.staticTexts["native 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertEqual(app.textFields.matching(identifier: "navigation.search.field").count, 1)
        assertIntegratedSearchRow(in: app)

        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        let clear = app.buttons["navigation.search.clear"]
        XCTAssertTrue(clear.waitForExistence(timeout: 3))
        clear.tap()
        XCTAssertEqual(search.value as? String, "搜索")
        XCTAssertTrue(app.keyboards.firstMatch.exists)

        let cancel = app.buttons["navigation.search.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        cancel.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.tabBars.buttons["搜索"].isSelected)
        XCTAssertEqual(app.textFields.matching(identifier: "navigation.search.field").count, 1)
    }

    func testOpeningResultDuringActiveSearchRestoresQueryAndFilters() {
        let app = launchFixture()
        let search = app.textFields["navigation.search.field"]
        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        XCTAssertEqual(search.value as? String, "滚动位置测试")
        app.staticTexts["结果 1"].tap()
        XCTAssertTrue(app.staticTexts["fixture.search.detail"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.textFields.matching(identifier: "navigation.search.field").count, 0)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))

        app.buttons["fixture.search.back"].tap()
        XCTAssertTrue(app.staticTexts["结果 1"].waitForExistence(timeout: 3))
        assertIntegratedSearchRow(in: app)
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        XCTAssertEqual(app.textFields.matching(identifier: "navigation.search.field").count, 1)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        search.tap()
        XCTAssertEqual(search.value as? String, "滚动位置测试")
    }

    func testLeavingActiveSearchRestoresRootTabsAndFilters() {
        let app = launchFixture()
        let search = app.textFields["navigation.search.field"]
        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        app.buttons["navigation.search.cancel"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        app.scrollViews.firstMatch.swipeUp()
        assertIntegratedSearchRow(in: app)

        app.scrollViews.firstMatch.swipeDown()

        for tab in ["首页", "动态", "直播"] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(search.waitForNonExistence(timeout: 3))
            XCTAssertFalse(app.keyboards.firstMatch.exists)
            app.tabBars.buttons["搜索"].tap()
            XCTAssertTrue(search.waitForExistence(timeout: 3))
            XCTAssertEqual(app.textFields.matching(identifier: "navigation.search.field").count, 1)
            XCTAssertFalse(app.keyboards.firstMatch.exists)
        }
    }

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

    func testIntegratedSearchRemainsInToolbarAfterPresentationAndResultUpdates() {
        let app = launchFixture()
        assertIntegratedSearchRow(in: app)
        let search = app.textFields["navigation.search.field"]
        for index in 1...3 {
            search.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
            search.typeText(" row\(index)\n")
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
            assertIntegratedSearchRow(in: app)
            search.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
            let close = app.buttons["navigation.search.cancel"]
            XCTAssertTrue(close.waitForExistence(timeout: 3))
            close.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
            assertIntegratedSearchRow(in: app)
        }
        app.buttons["search.filters.menu"].tap()
        app.buttons["最新发布"].tap()
        assertIntegratedSearchRow(in: app)
        app.tabBars.buttons["首页"].tap()
        app.tabBars.buttons["搜索"].tap()
        assertIntegratedSearchRow(in: app)
    }

    func testIntegratedSearchStaysVisibleDuringRepeatedScrolling() {
        let app = launchFixture()
        let scroll = app.scrollViews.firstMatch
        let search = app.textFields["navigation.search.field"]
        let query = search.value as? String
        for _ in 0..<5 {
            scroll.swipeUp()
            assertIntegratedSearchRow(in: app)
            XCTAssertTrue(search.isHittable)
            XCTAssertEqual(search.value as? String, query)
            scroll.swipeDown()
            assertIntegratedSearchRow(in: app)
            XCTAssertTrue(search.isHittable)
            XCTAssertFalse(app.keyboards.firstMatch.exists)
        }
    }

    func testMineSearchStaysInNavigationBarAndRetainsTextAfterSubmit() {
        let app = launchFixture()
        app.tabBars.buttons["我的"].tap()
        let field = app.textFields["navigation.search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertTrue(app.navigationBars.firstMatch.frame.contains(field.frame))
        field.tap()
        field.typeText("设置\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertEqual(field.value as? String, "设置")
        XCTAssertTrue(app.navigationBars.firstMatch.frame.contains(field.frame))
        field.tap()
        app.buttons["navigation.search.cancel"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertEqual(field.value as? String, "搜索我的页功能")
    }

    func testToolbarSearchUsesSpaceFreedByAbsentButtons() {
        let app = launchFixture()
        let field = app.textFields["navigation.search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        let searchWidth = field.frame.width
        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertTrue(app.navigationBars.firstMatch.frame.contains(field.frame))
        XCTAssertGreaterThan(field.frame.width, searchWidth + 60,
                             "Without trailing actions the search input should use the freed space")
    }

    func testSearchFiltersShowBothGroupsAndCurrentSelectionsInOneMenu() {
        let app = launchFixture()
        let filters = app.buttons["search.filters.menu"]
        XCTAssertEqual(filters.value as? String, "视频，综合排序")
        filters.tap()
        for title in ["综合内容", "视频", "番剧", "影视", "专栏", "UP主",
                      "综合排序", "最多播放", "最新发布", "最多收藏"] {
            XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 3), title)
        }
        app.buttons["最新发布"].tap()
        XCTAssertEqual(filters.value as? String, "视频，最新发布")
        filters.tap()
        app.buttons["专栏"].tap()
        XCTAssertEqual(filters.value as? String, "专栏，当前类型不支持排序")
        filters.tap()
        XCTAssertFalse(app.buttons["最多播放"].isEnabled)
        XCTAssertFalse(app.buttons["最新发布"].isEnabled)
    }

    private func assertIntegratedSearchRow(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let search = app.textFields["navigation.search.field"]
        let filters = app.buttons["search.filters.menu"]
        XCTAssertTrue(search.waitForExistence(timeout: 3), file: file, line: line)
        XCTAssertTrue(filters.waitForExistence(timeout: 3), file: file, line: line)
        let navigationBar = app.navigationBars.firstMatch
        XCTAssertTrue(navigationBar.exists, file: file, line: line)
        XCTAssertTrue(navigationBar.frame.contains(search.frame),
                      "Search must be inside the navigation bar: \(search.frame), bar: \(navigationBar.frame)",
                      file: file, line: line)
        let rowAligned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(search.frame.midY - filters.frame.midY) < 8
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rowAligned], timeout: 5), .completed,
                       "search: \(search.frame), filters: \(filters.frame)", file: file, line: line)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Integrated search resting row"
        screenshot.lifetime = .keepAlways
        add(screenshot)
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
