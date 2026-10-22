import XCTest

@MainActor
final class HomeRecommendationFeedbackUITests: XCTestCase {
    func testShortTapStillOpensVideo() {
        let app = launch()
        card(1, app).tap()
        XCTAssertTrue(app.staticTexts["fixture.feedback.detail"].waitForExistence(timeout: 3))
    }

    func testNativeContextMenuReasonsRemoveOnlyCurrentCard() {
        // XCTest can take longer than the transient notice's lifetime to return
        // from a menu tap. Observe the real notice before arming fixture expiry.
        let app = launch(extra: ["--feedback-controlled-notice-expiration"])
        openMenu(on: card(1, app))
        XCTAssertTrue(app.buttons["屏蔽该 UP"].waitForExistence(timeout: 3))
        XCTAssertEqual(card(1, app).value as? String, "菜单已打开")
        screenshot(app, "Native feedback context menu")
        app.buttons["不感兴趣"].tap()
        let reason = app.buttons["不想看此类内容"]
        XCTAssertTrue(reason.waitForExistence(timeout: 3))
        reason.tap()
        let completed = app.images["fixture.feedback.message"]
        XCTAssertTrue(completed.waitForExistence(timeout: 3))
        XCTAssertEqual(completed.label, "将减少此类推荐")
        screenshot(app, "Glass completion icon")
        app.buttons["fixture.feedback.expireNotice"].tap()
        XCTAssertTrue(completed.waitForNonExistence(timeout: 5))
        XCTAssertFalse(card(1, app).exists)
        XCTAssertTrue(card(3, app).exists)
        XCTAssertFalse(app.staticTexts["将减少此类推荐"].exists)
    }

    func testFailedFeedbackKeepsCard() {
        let app = launch(extra: ["--feedback-failure"])
        openMenu(on: card(1, app))
        app.buttons["不感兴趣"].tap()
        app.buttons["不想看此类内容"].tap()
        XCTAssertTrue(app.staticTexts["fixture.feedback.message"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["fixture.feedback.message"].label.contains("失败"))
        XCTAssertTrue(card(1, app).exists)
        XCTAssertTrue(card(3, app).exists)
    }

    func testAnonymousLocalBlockPrunesAllSameUPCards() {
        let app = launch(extra: ["--feedback-anonymous"])
        openMenu(on: card(1, app))
        screenshot(app, "Anonymous native menu")
        XCTAssertFalse(app.buttons["不感兴趣"].exists)
        XCTAssertTrue(app.buttons["屏蔽该 UP"].waitForExistence(timeout: 3))
        app.buttons["屏蔽该 UP"].tap()
        let local = app.buttons["仅在本机屏蔽"]
        XCTAssertTrue(local.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["拉黑并同步到 Bilibili"].exists)
        local.tap()
        XCTAssertTrue(app.images["fixture.feedback.message"].waitForExistence(timeout: 3))
        screenshot(app, "Local block completion")
        XCTAssertTrue(card(1, app).waitForNonExistence(timeout: 3))
        XCTAssertFalse(card(3, app).exists)
        XCTAssertTrue(card(2, app).exists)
    }

    func testCancelBlockLeavesFeedAndShortTapIntact() {
        let app = launch()
        openMenu(on: card(1, app))
        app.buttons["屏蔽该 UP"].tap()
        XCTAssertTrue(app.buttons["拉黑并同步到 Bilibili"].waitForExistence(timeout: 3))
        screenshot(app, "Native block submenu")
        if app.buttons["取消"].exists {
            app.buttons["取消"].tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
        }
        XCTAssertTrue(card(1, app).exists)
        XCTAssertEqual(card(1, app).value as? String, "")
        card(1, app).tap()
        XCTAssertTrue(app.staticTexts["fixture.feedback.detail"].waitForExistence(timeout: 3))
    }

    func testScrollDoesNotOpenMenuAndFeedbackDoesNotResetScrollToTop() {
        let app = launch()
        let scroll = app.scrollViews["fixture.feedback.scroll"]
        scroll.swipeUp()
        XCTAssertFalse(app.buttons["屏蔽该 UP"].exists)
        XCTAssertFalse(app.staticTexts["fixture.feedback.detail"].exists)
        let visible = card(7, app)
        XCTAssertTrue(visible.waitForExistence(timeout: 3))
        XCTAssertTrue(visible.isHittable)
        let selectedID = visible.identifier
        // Press the visible cover, away from the transparent metadata gaps.
        visible.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).press(forDuration: 1.5)
        XCTAssertTrue(app.buttons["不感兴趣"].waitForExistence(timeout: 3))
        app.buttons["不感兴趣"].tap()
        app.buttons["不想看此类内容"].tap()
        XCTAssertTrue(app.buttons[selectedID].waitForNonExistence(timeout: 3))
        XCTAssertFalse(card(1, app).isHittable)
    }

    private func launch(extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "homeFeedback", "--ui-test-enable-animations"] + extra
        app.launch()
        XCTAssertTrue(card(1, app).waitForExistence(timeout: 10), app.debugDescription)
        addTeardownBlock { app.terminate() }
        return app
    }

    private func card(_ number: Int, _ app: XCUIApplication) -> XCUIElement {
        app.buttons["fixture.feedback.card.fixture-\(number)"]
    }

    private func openMenu(on card: XCUIElement) {
        XCTAssertTrue(card.isHittable)
        // Target the visible cover rather than a transparent metadata gap.
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
            .press(forDuration: 1.5)
    }

    private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
