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
        open.press(forDuration: 1.0)

        let copy = app.buttons["复制评论"]
        let reply = app.buttons["回复"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(reply.waitForExistence(timeout: 5), app.debugDescription)
        reply.tap()

        let editor = app.textViews["dynamic.comment.composer.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 2))
        XCTAssertFalse(reply.exists)
    }
}
