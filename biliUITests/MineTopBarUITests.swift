import XCTest

@MainActor
final class MineTopBarUITests: XCTestCase {
    private func nativeSearchButton(in app: XCUIApplication) -> XCUIElement {
        app.navigationBars.buttons.matching(
            NSPredicate(format: "label IN %@ OR identifier == %@", ["Search", "搜索", "搜索我的页功能"], "mine.search.button")
        ).firstMatch
    }

    private func nativeSearchField(in app: XCUIApplication) -> XCUIElement {
        app.searchFields.firstMatch
    }

    private func nativeCloseSearchButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "label IN %@ OR identifier == %@", ["close", "Close", "Cancel", "Dismiss", "关闭", "取消"], "mine.search.cancel")
        ).firstMatch
    }

    private func launchFixture() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "mineTopBar"]
        app.launch()
        XCTAssertTrue(nativeSearchButton(in: app).waitForExistence(timeout: 20), app.debugDescription)
        addTeardownBlock { app.terminate() }
        return app
    }

    func testTitleAndGlassSearchButtonPresent() {
        let app = launchFixture()
        let title = app.staticTexts["mine.feed.title"]
        XCTAssertTrue(title.exists, app.debugDescription)
        XCTAssertEqual(title.label, "我的")

        let searchButton = nativeSearchButton(in: app)
        XCTAssertTrue(searchButton.exists, app.debugDescription)
        XCTAssertTrue(searchButton.isHittable, app.debugDescription)
        XCTAssertGreaterThan(searchButton.frame.minX, title.frame.maxX)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "mine-toolbar-idle"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testSearchButtonMorphsFieldFiltersClearAndCancelRestores() {
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
        let cancelButton = nativeCloseSearchButton(in: app)
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertGreaterThan(cancelButton.frame.minX, field.frame.maxX)

        field.tap()
        field.typeText("设置")
        XCTAssertEqual(field.value as? String, "设置")

        let expandedShot = XCTAttachment(screenshot: app.screenshot())
        expandedShot.name = "mine-toolbar-expanded-search"
        expandedShot.lifetime = .keepAlways
        add(expandedShot)

        let clearButton = field.buttons.firstMatch
        XCTAssertTrue(clearButton.waitForExistence(timeout: 3), app.debugDescription)
        clearButton.tap()
        XCTAssertTrue(field.exists, app.debugDescription)
        XCTAssertFalse(searchButton.exists)

        cancelButton.tap()
        XCTAssertTrue(searchButton.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(nativeSearchField(in: app).exists)
    }

    func testSearchSubmitDismissesKeyboardAndOutsideTapCollapsesEmptyField() {
        let app = launchFixture()
        let searchButton = nativeSearchButton(in: app)
        searchButton.tap()

        let field = nativeSearchField(in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        field.tap()
        field.typeText("播放\n")
        XCTAssertTrue(field.exists, app.debugDescription)

        let clearButton = field.buttons.firstMatch
        XCTAssertTrue(clearButton.waitForExistence(timeout: 3), app.debugDescription)
        clearButton.tap()

        let scrollContainer = app.collectionViews.firstMatch.exists
            ? app.collectionViews.firstMatch
            : app.tables.firstMatch
        XCTAssertTrue(scrollContainer.waitForExistence(timeout: 5), app.debugDescription)
        scrollContainer.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()

        XCTAssertTrue(searchButton.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(nativeSearchField(in: app).exists)
    }

    func testPushAndPopSecondaryPagePreservesMineTopBar() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-cc.bili.display.visibleRootTabs.v1", "(home,dynamic,mine)",
            "--ui-test-enable-animations"
        ]
        app.launch()
        addTeardownBlock { app.terminate() }

        let mineTab = app.tabBars.buttons["我的"]
        XCTAssertTrue(mineTab.waitForExistence(timeout: 15), app.debugDescription)
        mineTab.tap()

        let searchButton = nativeSearchButton(in: app)
        XCTAssertTrue(searchButton.waitForExistence(timeout: 10), app.debugDescription)
        let title = app.staticTexts["mine.feed.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), app.debugDescription)

        let interfaceRow = app.buttons["mine.settings.interface"]
        XCTAssertTrue(interfaceRow.waitForExistence(timeout: 5), app.debugDescription)
        interfaceRow.tap()

        XCTAssertFalse(title.waitForExistence(timeout: 1.5), app.debugDescription)
        let backButton = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: 5), app.debugDescription)
        backButton.tap()

        XCTAssertTrue(title.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(searchButton.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertGreaterThan(searchButton.frame.minX, title.frame.maxX)
        XCTAssertGreaterThanOrEqual(searchButton.frame.minX, 340)
    }

    func testScrolledTitleStaysHiddenAfterSearchCancel() {
        let app = launchFixture()
        let title = app.staticTexts["mine.feed.title"]
        XCTAssertTrue(title.exists, app.debugDescription)

        let scrollContainer = app.collectionViews.firstMatch.exists
            ? app.collectionViews.firstMatch
            : app.tables.firstMatch
        XCTAssertTrue(scrollContainer.waitForExistence(timeout: 5), app.debugDescription)

        for _ in 0..<4 where title.exists {
            scrollContainer.swipeUp()
        }
        XCTAssertFalse(title.exists, app.debugDescription)

        let searchButton = nativeSearchButton(in: app)
        searchButton.tap()
        let cancelButton = nativeCloseSearchButton(in: app)
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 5), app.debugDescription)
        cancelButton.tap()

        XCTAssertTrue(searchButton.waitForExistence(timeout: 5), app.debugDescription)
        // Wait past the title restore animation delay to ensure it stays hidden.
        let unexpectedTitle = title.waitForExistence(timeout: 1.0)
        XCTAssertFalse(unexpectedTitle, app.debugDescription)

        let scrolledCancelShot = XCTAttachment(screenshot: app.screenshot())
        scrolledCancelShot.name = "mine-scrolled-after-cancel"
        scrolledCancelShot.lifetime = .keepAlways
        add(scrolledCancelShot)

        // Also verify empty-field blur (tapping content area) keeps title hidden.
        searchButton.tap()
        XCTAssertTrue(nativeSearchField(in: app).waitForExistence(timeout: 5), app.debugDescription)
        scrollContainer.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        XCTAssertTrue(searchButton.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(title.waitForExistence(timeout: 1.0), app.debugDescription)

        for _ in 0..<6 where !title.exists {
            scrollContainer.swipeDown(velocity: .fast)
        }
        XCTAssertTrue(title.waitForExistence(timeout: 5), app.debugDescription)
    }

    func testHiddenMinePageKeepsSwitcherAndMorphsSearchBar() {
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
        let menuHittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == true"),
            object: modeMenu
        )
        XCTAssertEqual(XCTWaiter.wait(for: [menuHittable], timeout: 5), .completed, app.debugDescription)
        modeMenu.tap()
        let mineMenuItem = app.collectionViews.buttons["我的"]
        XCTAssertTrue(mineMenuItem.waitForExistence(timeout: 5), app.debugDescription)
        mineMenuItem.tap()

        let searchButton = nativeSearchButton(in: app)
        XCTAssertTrue(searchButton.waitForExistence(timeout: 10), app.debugDescription)
        let switcher = app.buttons["root.hiddenPageSwitcher"]
        XCTAssertTrue(switcher.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertGreaterThan(switcher.frame.minX, searchButton.frame.maxX)

        searchButton.tap()
        let field = nativeSearchField(in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        let cancelButton = nativeCloseSearchButton(in: app)
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertGreaterThan(cancelButton.frame.minX, field.frame.maxX)
        XCTAssertFalse(switcher.exists)

        let hiddenExpandedShot = XCTAttachment(screenshot: app.screenshot())
        hiddenExpandedShot.name = "mine-roottab-expanded-search"
        hiddenExpandedShot.lifetime = .keepAlways
        add(hiddenExpandedShot)

        cancelButton.tap()
        XCTAssertTrue(searchButton.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(switcher.waitForExistence(timeout: 5), app.debugDescription)

        switcher.tap()
        let homeItem = app.collectionViews.buttons["首页"]
        XCTAssertTrue(homeItem.waitForExistence(timeout: 5), app.debugDescription)
        homeItem.tap()
        XCTAssertTrue(modeMenu.waitForExistence(timeout: 5), app.debugDescription)
    }
}
