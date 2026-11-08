import XCTest

@MainActor
final class DynamicFeedTabsUITests: XCTestCase {

    /// First fixture launches on a cold simulator can take well over ten
    /// seconds before the first element appears; every test therefore waits on
    /// a stable landmark before interacting.
    private let launchTimeout: TimeInterval = 25

    private func launchFixture(_ scenario: String, visibleTabs: [String]? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", scenario]
        if let visibleTabs {
            app.launchArguments += [
                "-cc.bili.display.visibleDynamicFeedKinds.v1",
                "(" + visibleTabs.joined(separator: ",") + ")",
            ]
        }
        app.launch()
        let probe = app.staticTexts["fixture.dynamicTabs.config"]
        XCTAssertTrue(probe.waitForExistence(timeout: launchTimeout), app.debugDescription)
        return app
    }

    private func probeText(_ app: XCUIApplication) -> String? {
        app.staticTexts["fixture.dynamicTabs.config"].label
    }

    private func scrollToEntry(_ app: XCUIApplication) -> XCUIElement {
        // Form rows below the fold are not materialized in the accessibility
        // tree yet, so existence is checked between swipes.
        let entry = app.buttons["settings.dynamicFeedTabs.entry"]
        for _ in 0..<12 {
            if entry.exists && entry.isHittable { return entry }
            app.swipeUp()
        }
        XCTAssertTrue(entry.exists && entry.isHittable, app.debugDescription)
        return entry
    }

    private func scrollTo(_ app: XCUIApplication, _ element: XCUIElement) {
        for _ in 0..<8 where !element.isHittable {
            app.swipeUp()
        }
    }

    /// SwiftUI Form rows only flip the switch when the control itself is
    /// tapped; the row center is inert.
    private func tapSwitch(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    }

    private func waitToggleValue(_ element: XCUIElement, _ value: String, timeout: TimeInterval = 5) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in (element.value as? String) == value },
            object: nil
        )
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, element.debugDescription)
    }

    func testDefaultConfigurationShowsAllSegmentsInDefaultOrder() {
        // Seed explicitly: earlier settings tests persist their toggles in the
        // simulator container, and the launch-argument domain keeps this test
        // independent of that state.
        let app = launchFixture(
            "dynamicFeedTabs",
            visibleTabs: ["all", "video", "pgc", "article", "up"]
        )
        let pickerFound = app.segmentedControls["dynamic.feedPicker"].waitForExistence(timeout: 10)
            || app.otherElements["dynamic.feedPicker"].waitForExistence(timeout: 2)
        XCTAssertTrue(pickerFound, app.debugDescription)
        for title in ["全部", "投稿", "番剧", "专栏", "UP"] {
            XCTAssertTrue(app.buttons[title].exists, "缺少分段 \(title)：\(app.debugDescription)")
        }
        XCTAssertEqual(probeText(app), "all,video,pgc,article,up")
    }

    func testCustomConfigurationHidesKindsAndFollowsStoredOrder() {
        let app = launchFixture("dynamicFeedTabs", visibleTabs: ["up", "article"])
        let pickerFound = app.segmentedControls["dynamic.feedPicker"].waitForExistence(timeout: 10)
            || app.otherElements["dynamic.feedPicker"].waitForExistence(timeout: 2)
        XCTAssertTrue(pickerFound, app.debugDescription)
        XCTAssertTrue(app.buttons["UP"].exists)
        XCTAssertTrue(app.buttons["专栏"].exists)
        XCTAssertFalse(app.buttons["全部"].exists)
        XCTAssertFalse(app.buttons["投稿"].exists)
        XCTAssertFalse(app.buttons["番剧"].exists)
        XCTAssertEqual(probeText(app), "up,article")
    }

    func testSingleKindHidesToolbarAndShowsLargeTitle() {
        let app = launchFixture("dynamicFeedTabs", visibleTabs: ["video"])
        XCTAssertFalse(app.segmentedControls["dynamic.feedPicker"].exists)
        XCTAssertFalse(app.otherElements["dynamic.feedPicker"].exists)
        XCTAssertFalse(app.buttons["投稿"].exists)
        let navigationBar = app.navigationBars.firstMatch
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 5))
        XCTAssertTrue(navigationBar.staticTexts["动态"].exists, app.debugDescription)
        XCTAssertEqual(probeText(app), "video")
    }

    func testSettingsEntryTogglesVisibilityAndProtectsLastKind() {
        let app = launchFixture("dynamicFeedTabSettings", visibleTabs: ["video"])
        scrollToEntry(app).tap()

        let videoToggle = app.switches["settings.dynamicFeedTabs.toggle.video"]
        XCTAssertTrue(videoToggle.waitForExistence(timeout: 10), app.debugDescription)
        waitToggleValue(videoToggle, "1")
        // 至少保留一个显示：唯一可见选项的开关应被禁用。
        XCTAssertFalse(videoToggle.isEnabled, app.debugDescription)

        // 重新显示一个隐藏选项，按默认顺序插到投稿之前。
        let allToggle = app.switches["settings.dynamicFeedTabs.toggle.all"]
        XCTAssertTrue(allToggle.waitForExistence(timeout: 5))
        scrollTo(app, allToggle)
        tapSwitch(allToggle)
        waitToggleValue(allToggle, "1")
        XCTAssertEqual(probeText(app), "all,video")

        // 关闭后回到仅显示投稿；此时投稿仍可见，allToggle 回到已隐藏分组。
        scrollTo(app, allToggle)
        tapSwitch(allToggle)
        waitToggleValue(allToggle, "0")
        XCTAssertEqual(probeText(app), "video")
    }

    func testSettingsPageProvidesNativeEditModeForReordering() {
        let app = launchFixture("dynamicFeedTabSettings", visibleTabs: ["video", "up"])
        scrollToEntry(app).tap()

        let videoRow = app.switches["settings.dynamicFeedTabs.toggle.video"]
        XCTAssertTrue(videoRow.waitForExistence(timeout: 10), app.debugDescription)

        let editButton = app.buttons["settings.dynamicFeedTabs.edit"]
        XCTAssertTrue(editButton.waitForExistence(timeout: 5))
        editButton.tap()

        // 编辑模式下行改为纯文本并显示拖动排序控件（Toggle 暂避让）。
        let videoTextRow = app.staticTexts["settings.dynamicFeedTabs.row.video"]
        XCTAssertTrue(videoTextRow.waitForExistence(timeout: 8), app.debugDescription)

        editButton.tap()
        XCTAssertTrue(videoRow.waitForExistence(timeout: 8), app.debugDescription)
    }
}
