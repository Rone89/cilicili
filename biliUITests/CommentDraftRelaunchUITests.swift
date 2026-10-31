import XCTest

@MainActor
final class CommentDraftRelaunchUITests: XCTestCase {
    func testTextDraftSurvivesRelaunchAndStaysWithItsContentTarget() {
        let app = launchPersistent(clear: true)
        openComposer(in: app).typeText("restart draft A")
        dismissComposer(in: app)
        restart(app)
        XCTAssertEqual(openComposer(in: app).value as? String, "restart draft A")
        dismissComposer(in: app)
        app.buttons["草稿测试"].tap()
        app.buttons["切换评论目标"].tap()
        let other = openComposer(in: app)
        XCTAssertEqual(other.value as? String, "")
        other.typeText("draft B")
        dismissComposer(in: app)
        restart(app)
        XCTAssertEqual(openComposer(in: app).value as? String, "restart draft A")
    }

    func testSuccessfulSubmissionDoesNotRestoreSentTextAfterRelaunch() {
        let app = launchPersistent(clear: true)
        openComposer(in: app).typeText("send then clear")
        app.buttons["dynamic.comment.composer.send"].tap()
        XCTAssertTrue(app.textViews["dynamic.comment.composer.editor"].waitForNonExistence(timeout: 10))
        restart(app)
        XCTAssertEqual(openComposer(in: app).value as? String, "")
    }

    func testMissingRestoredImagesRequireExplicitAcknowledgmentBeforeSending() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-fixture", "libraryManagement", "--library-detail-menu",
            "--library-comment-composer", "--library-comment-missing-images",
        ]
        app.launch()
        XCTAssertTrue(app.buttons["library.video.BVfixture1"].waitForExistence(timeout: 15))
        XCTAssertEqual(openComposer(in: app).value as? String, "restored text")
        XCTAssertTrue(app.staticTexts["comment.draft.missingImages"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["dynamic.comment.composer.send"].isEnabled)
        let acknowledge = app.buttons["comment.draft.acknowledgeMissingImages"]
        XCTAssertTrue(acknowledge.waitForExistence(timeout: 5))
        XCTAssertTrue(acknowledge.isHittable)
        acknowledge.tap()
        XCTAssertTrue(app.buttons["dynamic.comment.composer.send"].isEnabled)
        XCTAssertEqual(app.textViews["dynamic.comment.composer.editor"].value as? String, "restored text")
    }

    private func launchPersistent(clear: Bool) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-fixture", "libraryManagement", "--library-detail-menu",
            "--library-comment-composer", "--library-comment-shared-drafts",
            "--ui-test-persistent-comment-drafts",
        ] + (clear ? ["--ui-test-clear-comment-drafts"] : [])
        app.launch()
        XCTAssertTrue(app.buttons["library.video.BVfixture1"].waitForExistence(timeout: 15))
        return app
    }

    private func restart(_ app: XCUIApplication) {
        app.terminate()
        app.launchArguments.removeAll { $0 == "--ui-test-clear-comment-drafts" }
        app.launch()
        XCTAssertTrue(app.buttons["library.video.BVfixture1"].waitForExistence(timeout: 15))
    }

    private func openComposer(in app: XCUIApplication) -> XCUIElement {
        app.buttons["video.detail.toolbar-comment"].tap()
        let editor = app.textViews["dynamic.comment.composer.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), app.debugDescription)
        return editor
    }

    private func dismissComposer(in app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.15)).tap()
        XCTAssertTrue(app.textViews["dynamic.comment.composer.editor"].waitForNonExistence(timeout: 10))
    }
}
