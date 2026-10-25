import XCTest

@MainActor
final class CommentSheetAppearanceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLightCommentsKeepLightPresentationUnderDarkVideoHost() {
        verify(startsDark: false)
    }

    func testDarkCommentsKeepDarkPresentationUnderLightHost() {
        verify(startsDark: true)
    }

    func testLightComposerFollowsAppAppearanceUnderDarkVideoHost() {
        verifyComposer(startsDark: false)
    }

    func testDarkComposerFollowsAppAppearanceUnderLightHost() {
        verifyComposer(startsDark: true)
    }

    private func verifyComposer(startsDark: Bool) {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-fixture", "commentAppearance",
            "--ui-test-enable-animations",
        ] + (startsDark ? ["--comment-appearance-dark"] : [])
        app.launch()
        defer { app.terminate() }

        let open = app.buttons["comment.appearance.composer"]
        XCTAssertTrue(open.waitForExistence(timeout: 8))
        for expected in [startsDark ? "dark" : "light", startsDark ? "light" : "dark"] {
            open.tap()
            assertNativeAppearance(expected, app: app, identifier: "comment.appearance.composerStyle")
            XCTAssertTrue(app.textViews["dynamic.comment.composer.editor"].waitForExistence(timeout: 5))
            capture(app, name: "comment-composer-\(expected)")
            // Dismiss through the real presentation backdrop, then reopen after an app setting change.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
            let dismissed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"),
                object: app.staticTexts["comment.appearance.composerStyle"]
            )
            XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
            app.buttons["comment.appearance.rootToggle"].tap()
        }
    }

    private func verify(startsDark: Bool) {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-fixture", "commentAppearance",
            "--ui-test-enable-animations",
        ] + (startsDark ? ["--comment-appearance-dark"] : [])
        app.launch()
        defer { app.terminate() }

        let open = app.buttons["comment.appearance.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 8))
        open.tap()

        let initial = startsDark ? "dark" : "light"
        assertNativeAppearance(initial, app: app)
        let navigationBar = app.navigationBars["评论外观验证"]
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 5))
        let window = app.windows.firstMatch
        let mediumTop = navigationBar.frame.minY
        XCTAssertGreaterThan(mediumTop, window.frame.height * 0.3, "The fixture must begin at the medium detent")
        capture(app, name: "comment-appearance-\(initial)-medium")

        // Drag the actual system sheet grabber, above its navigation bar.
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: window.frame.midX, dy: mediumTop - 12))
        let end = origin.withOffset(CGVector(dx: window.frame.midX, dy: window.frame.minY + 80))
        start.press(forDuration: 0.1, thenDragTo: end)

        let expanded = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                navigationBar.frame.minY < window.frame.height * 0.25
            },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expanded], timeout: 8), .completed, app.debugDescription)
        assertNativeAppearance(initial, app: app)
        capture(app, name: "comment-appearance-\(initial)-large")

        app.buttons["comment.appearance.toggle"].tap()
        let changed = startsDark ? "light" : "dark"
        assertNativeAppearance(changed, app: app)
        capture(app, name: "comment-appearance-\(changed)-large-after-toggle")
    }

    private func assertNativeAppearance(
        _ expected: String,
        app: XCUIApplication,
        identifier: String = "comment.appearance.nativeStyle"
    ) {
        let probe = app.staticTexts[identifier]
        XCTAssertTrue(probe.waitForExistence(timeout: 5))
        let matches = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "\(expected)/\(expected)"),
            object: probe
        )
        XCTAssertEqual(XCTWaiter.wait(for: [matches], timeout: 8), .completed, app.debugDescription)
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
