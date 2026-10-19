import XCTest

@MainActor
final class RootTabScrollUITests: XCTestCase {
    private let tabs = ["首页", "动态", "直播", "搜索", "我的"]

    func testSingleHomeHasNoTabBarAfterReturningFromMine() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-cc.bili.display.visibleRootTabs.v1", "(home)",
            "-cc.bili.home.avatarNavigationExperimentEnabled.v1", "YES"
        ]
        app.launch()
        let more = app.buttons["更多页面"]
        XCTAssertTrue(more.waitForExistence(timeout: 15))
        XCTAssertEqual(app.tabBars.count, 0)
        more.tap()
        app.buttons["我的"].tap()
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        XCTAssertEqual(app.tabBars.count, 0)
    }

    func testEnablingTabFromStandaloneHomePreservesSettingsScroll() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-cc.bili.display.visibleRootTabs.v1", "(home)",
            "-cc.bili.home.avatarNavigationExperimentEnabled.v1", "YES"
        ]
        app.launch()
        let more = app.buttons["更多页面"]
        XCTAssertTrue(more.waitForExistence(timeout: 15))
        more.tap()
        app.buttons["我的"].tap()
        let interface = app.buttons["mine.settings.interface"]
        for _ in 0..<6 where !interface.isHittable { app.swipeUp() }
        XCTAssertTrue(interface.isHittable)
        interface.tap()
        XCTAssertEqual(app.tabBars.count, 0)
        let disclosure = app.buttons["底部 Tab 显示"]
        for _ in 0..<8 where !disclosure.isHittable { app.swipeUp() }
        XCTAssertTrue(disclosure.isHittable)
        disclosure.tap()
        let toggle = app.switches["settings.rootTabs.dynamic"]
        for _ in 0..<4 where !toggle.isHittable { app.swipeUp() }
        XCTAssertTrue(toggle.isHittable)
        let previousY = toggle.frame.minY
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertEqual(toggle.value as? String, "1", app.debugDescription)
        XCTAssertEqual(toggle.frame.minY, previousY, accuracy: 3)
        XCTAssertEqual(app.tabBars.count, 0)
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
    }

    func testRootTabReselectionScrollsToTopWithoutRefresh() {
        verifyReselection(arguments: [])
    }

    func testDynamicTabReselectionScrollsToTopWithoutRefresh() {
        verifyReselection(arguments: [], selectedTabs: ["动态"])
    }

    func testDynamicTabReselectionWithMinimizedTabBar() {
        verifyReselection(arguments: ["--test-minimize"], selectedTabs: ["动态"])
    }

    func testReselectionWithMinimizedTabBar() {
        verifyReselection(arguments: ["--test-minimize"])
    }

    func testReselectionWithReduceMotion() {
        continueAfterFailure = false
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        let toggle = openReduceMotion(in: settings)
        let original = toggle.value as? String
        XCTAssertTrue(original == "0" || original == "1")
        if original != "1" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        let enabled = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in toggle.value as? String == "1" }, object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        defer {
            settings.activate()
            // Settings may return to its root after the app under test takes focus.
            // Resolve the current page again instead of reusing the previous AX node.
            let restoredToggle = openReduceMotion(in: settings)
            if restoredToggle.value as? String != original {
                restoredToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            }
            let restored = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in restoredToggle.value as? String == original }, object: nil
            )
            XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed)
        }
        verifyReselection(arguments: ["--test-reduce-motion"])
    }

    func testFormDoesNotReplayOldRequestAfterPushAndSwitch() {
        let app = launch()
        select("我的", in: app)
        mainScroll(in: app).swipeUp()
        app.tabBars.buttons["我的"].tap()
        assertOffset(0, in: app, message: "Mine first request")
        let scroll = mainScroll(in: app)
        scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
            .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)),
                   withVelocity: .slow, thenHoldForDuration: 0.1)
        let before = offset(app)
        app.buttons["fixture.root.detail"].tap()
        app.buttons["返回"].tap()
        XCTAssertEqual(offset(app), before, accuracy: 8)
        select("首页", in: app)
        select("我的", in: app)
        XCTAssertEqual(offset(app), before, accuracy: 8)
    }

    func testOrdinaryTabSwitchesKeepEveryRootOffset() {
        let app = launch()
        for tab in tabs {
            select(tab, in: app)
            mainScroll(in: app).swipeUp()
            let before = offset(app)
            XCTAssertGreaterThan(before, 50, tab)
            let other = tab == "首页" ? "动态" : "首页"
            select(other, in: app)
            select(tab, in: app)
            XCTAssertEqual(offset(app), before, accuracy: 8, tab)
        }
    }

    func testPushPopKeepsEveryRootOffsetAndHidesTabs() {
        let app = launch()
        for tab in tabs {
            select(tab, in: app)
            let scroll = mainScroll(in: app)
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
                .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)),
                       withVelocity: .slow, thenHoldForDuration: 0.1)
            let before = offset(app)
            app.buttons["fixture.root.detail"].tap()
            XCTAssertTrue(app.staticTexts["二级页面"].waitForExistence(timeout: 3))
            XCTAssertFalse(app.tabBars.firstMatch.exists)
            app.buttons["fixture.root.reselect"].tap()
            XCTAssertTrue(app.staticTexts["二级页面"].exists)
            XCTAssertEqual(offset(app), before, accuracy: 8, tab)
            app.buttons["返回"].tap()
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 3))
            XCTAssertEqual(offset(app), before, accuracy: 8, tab)
        }
    }

    func testActiveSearchScrollRequestKeepsQueryKeyboardAndFilters() {
        let app = launch()
        select("搜索", in: app)
        mainScroll(in: app).swipeUp()
        mainScroll(in: app).swipeUp()
        app.buttons["fixture.root.focusSearch"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        let search = app.searchFields.firstMatch
        let query = search.value as? String
        let scope = app.buttons["搜索类型"].value as? String
        let order = app.buttons["排序方式"].value as? String
        XCTAssertGreaterThan(offset(app), 50)
        // The software keyboard covers the TabBar. Exercise the same selection Binding.
        app.buttons["fixture.root.reselect"].tap()
        assertOffset(0, in: app, message: "Active search")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertEqual(search.value as? String, query)
        XCTAssertEqual(app.buttons["搜索类型"].value as? String, scope)
        XCTAssertEqual(app.buttons["排序方式"].value as? String, order)
        XCTAssertEqual(app.searchFields.count, 1)
    }

    private func verifyReselection(arguments: [String], selectedTabs: [String]? = nil) {
        let app = launch(arguments: arguments)
        for tab in selectedTabs ?? tabs {
            select(tab, in: app)
            if tab == "直播" {
                XCTAssertTrue(app.staticTexts["直播内容 1"].waitForExistence(timeout: 10))
            }
            let top = offset(app)
            let scroll = mainScroll(in: app)
            scroll.swipeUp()
            scroll.swipeUp()
            XCTAssertGreaterThan(offset(app), top + 50, tab)
            let requests = app.staticTexts["fixture.root.requests"].label
            app.tabBars.buttons[tab].tap()
            assertOffset(top, in: app, message: tab)
            XCTAssertFalse(app.keyboards.firstMatch.exists)
            XCTAssertEqual(app.staticTexts["fixture.root.requests"].label, requests, "Reselection must not refresh \(tab)")
            app.tabBars.buttons[tab].tap()
            assertOffset(top, in: app, message: "Already at top: \(tab)")
            XCTAssertFalse(app.keyboards.firstMatch.exists)
            XCTAssertEqual(app.staticTexts["fixture.root.requests"].label, requests)
            XCTAssertTrue(app.tabBars.firstMatch.exists)
            if tab != "搜索" {
                XCTAssertTrue(app.tabBars.buttons["首页"].exists)
                XCTAssertTrue(app.tabBars.buttons["我的"].exists)
            } else {
                XCTAssertTrue(app.buttons["搜索类型"].isHittable)
                XCTAssertTrue(app.buttons["排序方式"].isHittable)
                // In the minimized Search role, the field may be represented by a button.
                XCTAssertEqual(app.staticTexts["fixture.root.query"].label, "保留关键词")
            }
        }
    }

    private func openReduceMotion(in settings: XCUIApplication) -> XCUIElement {
        let labels = ["Reduce Motion", "减弱动态效果"]
        func toggle() -> XCUIElement {
            settings.switches.matching(NSPredicate(format: "label IN %@", labels)).firstMatch
        }
        if toggle().waitForExistence(timeout: 3) { return toggle() }
        let motionLabels = ["Motion", "动态效果"]
        let motion = settings.staticTexts.matching(NSPredicate(format: "label IN %@", motionLabels)).firstMatch
        if !motion.waitForExistence(timeout: 2) {
            let accessibility = settings.staticTexts.matching(
                NSPredicate(format: "label IN %@", ["Accessibility", "辅助功能"])
            ).firstMatch
            for _ in 0..<5 { settings.swipeDown() }
            for _ in 0..<8 {
                if accessibility.exists && accessibility.isHittable { break }
                settings.swipeUp()
            }
            XCTAssertTrue(accessibility.waitForExistence(timeout: 5))
            accessibility.tap()
        }
        XCTAssertTrue(motion.waitForExistence(timeout: 5))
        motion.tap()
        XCTAssertTrue(toggle().waitForExistence(timeout: 5))
        return toggle()
    }

    private func launch(arguments: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "rootTabScroll", "--ui-test-enable-animations"] + arguments
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["首页"].waitForExistence(timeout: 5))
        if arguments.contains("--test-reduce-motion") {
            XCTAssertEqual(app.staticTexts["fixture.root.reduceMotion"].label, "1")
        }
        addTeardownBlock { app.terminate() }
        return app
    }

    private func select(_ tab: String, in app: XCUIApplication) {
        if !app.tabBars.buttons[tab].exists { app.tabBars.buttons.firstMatch.tap() }
        XCTAssertTrue(app.tabBars.buttons[tab].waitForExistence(timeout: 3))
        if !app.tabBars.buttons[tab].isSelected { app.tabBars.buttons[tab].tap() }
        if tab == "直播" {
            XCTAssertTrue(app.staticTexts["直播内容 1"].waitForExistence(timeout: 10))
        }
    }

    private func mainScroll(in app: XCUIApplication) -> XCUIElement {
        let searchResults = app.scrollViews["search.results"]
        let scroll = searchResults.exists ? searchResults
            : (app.scrollViews.firstMatch.exists ? app.scrollViews.firstMatch : app.collectionViews.firstMatch)
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        return scroll
    }

    private func assertOffset(_ target: Double, in app: XCUIApplication, message: String) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(self.offset(app) - target) < 8
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed,
                       "\(message): expected \(target), got \(offset(app))")
    }

    private func offset(_ app: XCUIApplication) -> Double {
        Double(app.staticTexts["fixture.root.offset"].label) ?? -999
    }
}
