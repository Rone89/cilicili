import XCTest

@MainActor
final class CommentLocationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testVideoCommentReplyAndDialogShowServiceRegions() {
        verify(isDynamic: false)
    }

    func testDynamicCommentReplyAndDialogShowServiceRegions() {
        verify(isDynamic: true)
    }

    private func verify(isDynamic: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "commentLocation"]
            + (isDynamic ? ["--comment-location-dynamic"] : [])
        app.launch()
        defer { app.terminate() }

        for region in ["广东", "上海", "北京", "四川"] {
            let metadata = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "IP属地：\(region)")
            ).firstMatch
            XCTAssertTrue(metadata.waitForExistence(timeout: 5), app.debugDescription)
        }
        XCTAssertTrue(app.staticTexts["无属地的评论"].exists)
        XCTAssertEqual(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "IP属地：")).count,
            4,
            "The comment without service metadata must not gain a region label"
        )
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = isDynamic ? "Dynamic comment regions" : "Video comment regions"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
