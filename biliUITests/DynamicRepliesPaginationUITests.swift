import XCTest

@MainActor
final class DynamicRepliesPaginationUITests: XCTestCase {
    func testMoreRepliesAppearBelowCurrentBottomInDynamicDetailSheet() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "dynamicReplies", "--ui-test-reset-state"]
        app.launch()
        defer { app.terminate() }

        app.buttons["打开动态详情"].tap()
        let openReplies = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "14 条回复")).firstMatch
        XCTAssertTrue(openReplies.waitForExistence(timeout: 5))
        openReplies.tap()

        let repliesScroll = app.scrollViews.element(boundBy: 1)
        XCTAssertTrue(repliesScroll.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["分页回复1"].waitForExistence(timeout: 5))
        let more = app.buttons["查看更多回复"]
        for _ in 0..<12 where !more.isHittable { repliesScroll.swipeUp() }
        XCTAssertTrue(more.isHittable)
        capture(app, name: "Dynamic replies before loading page 2")
        more.tap()
        XCTAssertTrue(more.waitForNonExistence(timeout: 5))

        let lastReply = app.staticTexts["分页回复14"]
        for _ in 0..<3 where !lastReply.isHittable { repliesScroll.swipeUp() }
        XCTAssertTrue(lastReply.isHittable, "Next-page replies must appear at the bottom, rather than above the loaded page")
        let previousReply = app.staticTexts["分页回复12"]
        XCTAssertTrue(previousReply.isHittable)
        XCTAssertLessThan(previousReply.frame.minY, lastReply.frame.minY)
        capture(app, name: "Dynamic replies page 2 appended at bottom")
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
