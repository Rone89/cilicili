import XCTest

@MainActor
final class CommentSpacingUITests: XCTestCase {
    func testUnifiedSpacingAndLongPress() { verify(accessibility: false) }
    func testAccessibilitySpacing() { verify(accessibility: true) }

    private func verify(accessibility: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "commentSpacing"] + (accessibility ? ["--comment-spacing-accessibility"] : [])
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["comment.height.dynamic.0"].waitForExistence(timeout: 5))
        capture(app, name: "Unified-comment-spacing-\(accessibility ? "accessibility" : "standard")")
        for index in 0..<9 {
            let dynamic = height("dynamic.\(index)", app: app)
            let video = height("video.\(index)", app: app)
            XCTAssertEqual(dynamic, video, accuracy: 1, "sample \(index)")
        }
        returnToTop(app)
        _ = height("dynamic.1", app: app)
        let sample = app.descendants(matching: .any)["comment.sample.dynamic.1"]
        let visible = sample.frame.intersection(app.scrollViews.firstMatch.frame)
            .intersection(app.windows.firstMatch.frame.insetBy(dx: 24, dy: 100))
        XCTAssertFalse(visible.isNull, "Long press must target the visible part of accessibility-sized text")
        XCTAssertGreaterThan(visible.height, 0)
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: visible.minX + min(24, visible.width / 2), dy: visible.minY + min(12, visible.height / 2))).press(forDuration: 1)
        XCTAssertTrue(app.buttons["复制评论"].waitForExistence(timeout: 3))
        app.buttons["复制评论"].tap()

    }
    private func height(_ id: String, app: XCUIApplication) -> Double {
        let metric = app.staticTexts["comment.height.\(id)"]
        for _ in 0..<30 {
            if metric.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(metric.isHittable, id)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in (Double(metric.label) ?? 0) > 0 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 3), .completed)
        return Double(metric.label) ?? -1
    }
    private func returnToTop(_ app: XCUIApplication) {
        let metric = app.staticTexts["comment.height.dynamic.0"]
        for _ in 0..<30 {
            if metric.isHittable { break }
            app.scrollViews.firstMatch.swipeDown()
        }
        XCTAssertTrue(metric.isHittable)
    }
    private func capture(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
