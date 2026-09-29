import XCTest

final class CommentActionFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testReplyActionOpensComposer() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-fixture", "commentAction",
            "--ui-test-enable-animations",
        ]
        app.launch()

        let open = app.buttons["ui.commentAction.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 3))
        open.press(forDuration: 0.6)

        let copy = app.buttons["复制评论"]
        let reply = app.buttons["回复"]
        XCTAssertTrue(copy.waitForExistence(timeout: 2))
        XCTAssertTrue(reply.waitForExistence(timeout: 2))
        reply.tap()

        let editor = app.textViews["dynamic.comment.composer.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 2))
        XCTAssertFalse(reply.exists)
    }
}
