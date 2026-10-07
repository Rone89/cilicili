import XCTest

@MainActor
final class SearchScrollRetentionUITests: XCTestCase {
    func testCancelAfterSubmittedSearchRestoresHotSearches() {
        let app = launchFixture()
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText(" native\n")
        XCTAssertTrue(app.staticTexts["滚动位置测试 native 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))

        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        app.buttons.matching(NSPredicate(format: "label IN %@", ["关闭", "Close", "取消", "Cancel"])).firstMatch.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["大家都在搜"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["热门搜索，热搜保留测试"].exists)
        XCTAssertFalse(app.staticTexts["滚动位置测试 native 1"].exists)
        XCTAssertEqual(app.searchFields.count, 1)
        XCTAssertTrue(app.tabBars.buttons["搜索"].isSelected)

        app.tabBars.buttons["首页"].tap()
        app.tabBars.buttons["搜索"].tap()
        XCTAssertTrue(app.staticTexts["大家都在搜"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["热门搜索，热搜保留测试"].exists)
    }

    func testNativeSearchPresentationSubmitCancelAndClear() {
        let app = launchFixture()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        XCTAssertEqual(app.searchFields.count, 1)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        let normalScreenshot = XCTAttachment(screenshot: app.screenshot())
        normalScreenshot.name = "Native search resting state"
        normalScreenshot.lifetime = .keepAlways
        add(normalScreenshot)

        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["搜索类型"].isHittable)
        XCTAssertTrue(app.buttons["排序方式"].isHittable)
        XCTAssertEqual(app.buttons.matching(identifier: "搜索类型").count, 1)
        XCTAssertEqual(app.buttons.matching(identifier: "排序方式").count, 1)
        let keyboard = app.keyboards.firstMatch
        let filtersAboveKeyboard = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                let bottom = min(keyboard.frame.minY, app.frame.maxY)
                return app.buttons["搜索类型"].frame.maxY <= bottom
                    && app.buttons["排序方式"].frame.maxY <= bottom
                    && app.buttons["搜索类型"].frame.maxX < app.buttons["排序方式"].frame.minX
            },
            object: nil
        )
        let keyboardLayoutResult = XCTWaiter.wait(for: [filtersAboveKeyboard], timeout: 5)
        let activeScreenshot = XCTAttachment(screenshot: app.screenshot())
        activeScreenshot.name = "Native search presentation"
        activeScreenshot.lifetime = .keepAlways
        add(activeScreenshot)
        XCTAssertEqual(keyboardLayoutResult, .completed,
                       "keyboard: \(keyboard.frame), app: \(app.frame), scope: \(app.buttons["搜索类型"].frame)")
        search.typeText(" native\n")
        XCTAssertTrue(app.staticTexts["滚动位置测试 native 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertEqual(app.searchFields.count, 1)
        XCTAssertTrue(app.buttons["搜索类型"].isHittable)
        XCTAssertTrue(app.buttons["排序方式"].isHittable)

        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        let clear = search.buttons.firstMatch
        XCTAssertTrue(clear.waitForExistence(timeout: 3))
        clear.tap()
        XCTAssertEqual(search.value as? String, "搜索")
        XCTAssertTrue(app.keyboards.firstMatch.exists)

        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["关闭", "Close", "取消", "Cancel"])).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        cancel.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.tabBars.buttons["搜索"].isSelected)
        XCTAssertEqual(app.searchFields.count, 1)
    }

    func testOpeningResultDuringActiveSearchRestoresQueryAndFilters() {
        let app = launchFixture()
        let search = app.searchFields.firstMatch
        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        XCTAssertEqual(search.value as? String, "滚动位置测试")
        app.staticTexts["结果 1"].tap()
        XCTAssertTrue(app.staticTexts["fixture.search.detail"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.searchFields.count, 0)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))

        app.buttons["fixture.search.back"].tap()
        XCTAssertTrue(app.staticTexts["结果 1"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["搜索类型"].isHittable)
        XCTAssertTrue(app.buttons["排序方式"].isHittable)
        // The restored scroll offset can minimize the native search toolbar.
        if !search.exists { app.scrollViews.firstMatch.swipeDown() }
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        XCTAssertEqual(app.searchFields.count, 1)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        search.tap()
        XCTAssertEqual(search.value as? String, "滚动位置测试")
    }

    func testLeavingActiveSearchRestoresRootTabsAndFilters() {
        let app = launchFixture()
        let search = app.searchFields.firstMatch
        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        app.buttons.matching(NSPredicate(format: "label IN %@", ["关闭", "Close", "取消", "Cancel"])).firstMatch.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        app.scrollViews.firstMatch.swipeUp()
        XCTAssertTrue(app.buttons["搜索类型"].isHittable)
        XCTAssertTrue(app.buttons["排序方式"].isHittable)

        app.scrollViews.firstMatch.swipeDown()

        for tab in ["首页", "动态", "直播", "我的"] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(search.waitForNonExistence(timeout: 3))
            XCTAssertFalse(app.keyboards.firstMatch.exists)
            app.tabBars.buttons["搜索"].tap()
            XCTAssertTrue(search.waitForExistence(timeout: 3))
            XCTAssertEqual(app.searchFields.count, 1)
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
