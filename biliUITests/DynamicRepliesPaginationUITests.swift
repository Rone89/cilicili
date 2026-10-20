import XCTest

@MainActor
final class DynamicRepliesPaginationUITests: XCTestCase {
    func testAvatarAndMentionPresentProfileSheetAndReturnToReplies() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "dynamicReplies", "--ui-test-reset-state", "--ui-test-enable-animations"]
        app.launch()
        defer { app.terminate() }

        app.buttons["打开动态详情"].tap()
        let replies = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "14 条回复")).firstMatch
        XCTAssertTrue(replies.waitForExistence(timeout: 5))
        replies.tap()
        XCTAssertTrue(app.buttons["刷新评论"].waitForExistence(timeout: 5), app.debugDescription)
        let repliesScroll = app.scrollViews["dynamic.replies.scroll"]
        let firstReply = repliesScroll.descendants(matching: .any)["分页回复1"].firstMatch
        XCTAssertTrue(firstReply.waitForExistence(timeout: 10), app.debugDescription)

        let avatar = app.buttons.matching(identifier: "查看 分页用户100 的个人主页").element(boundBy: 1)
        XCTAssertTrue(avatar.waitForExistence(timeout: 5))
        XCTAssertTrue(avatar.isHittable)
        avatar.tap()
        let close = app.buttons["comment.profile.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), app.debugDescription)
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 3))
        XCTAssertTrue(avatar.isHittable)

        let mention = app.buttons.matching(identifier: "@提及用户").element(boundBy: 1)
        XCTAssertTrue(mention.waitForExistence(timeout: 3))
        mention.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 35, dy: mention.frame.height / 2)).tap()
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 3))
        XCTAssertTrue(firstReply.waitForExistence(timeout: 5))
        let visibleAvatar = app.buttons.matching(identifier: "查看 分页用户100 的个人主页")
            .element(boundBy: 1)
        XCTAssertTrue(visibleAvatar.waitForExistence(timeout: 3))
        XCTAssertTrue(visibleAvatar.isHittable)
    }

    func testMoreRepliesAppearBelowCurrentBottomInDynamicDetailSheet() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "dynamicReplies", "--ui-test-reset-state", "--ui-test-enable-animations"]
        app.launch()
        defer { app.terminate() }

        app.buttons["打开动态详情"].tap()
        let openReplies = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "14 条回复")).firstMatch
        XCTAssertTrue(openReplies.waitForExistence(timeout: 5))
        openReplies.tap()

        let repliesScroll = app.scrollViews["dynamic.replies.scroll"]
        XCTAssertTrue(repliesScroll.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["刷新评论"].waitForExistence(timeout: 5), app.debugDescription)
        let firstReply = app.descendants(matching: .any)["分页回复1"]
        for _ in 0..<12 where !firstReply.exists { repliesScroll.swipeUp() }
        XCTAssertTrue(firstReply.waitForExistence(timeout: 5), app.debugDescription)
        let more = app.buttons["查看更多回复"]
        for _ in 0..<12 where !more.isHittable { repliesScroll.swipeUp() }
        XCTAssertTrue(more.isHittable)
        capture(app, name: "Dynamic replies before loading page 2")
        more.tap()
        XCTAssertTrue(more.waitForNonExistence(timeout: 5))
        let loading = repliesScroll.staticTexts["正在加载更多回复"].firstMatch
        XCTAssertTrue(loading.waitForNonExistence(timeout: 10), app.debugDescription)

        let lastReply = app.descendants(matching: .any)["分页回复14"]
        for _ in 0..<3 where !lastReply.isHittable { repliesScroll.swipeUp() }
        XCTAssertTrue(lastReply.isHittable, "Next-page replies must appear at the bottom, rather than above the loaded page")
        let previousReply = app.descendants(matching: .any)["分页回复12"]
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
