import XCTest

@MainActor
final class CommentSpacingUITests: XCTestCase {
    func testLiveSpacingToggleAndLongPress() { verify(accessibility: false) }
    func testAccessibilitySpacing() { verify(accessibility: true) }

    private func verify(accessibility: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "commentSpacing"] + (accessibility ? ["--comment-spacing-accessibility"] : [])
        app.launch()
        defer { app.terminate() }
        let toggle = app.descendants(matching: .any)["comment.spacing.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        var off: [String: Double] = [:]
        for index in 0..<9 {
            for kind in ["dynamic", "video"] { off["\(kind).\(index)"] = height("\(kind).\(index)", app: app) }
        }
        toggle.tap()
        returnToTop(app)
        capture(app, name: "Unified-comment-spacing-\(accessibility ? "accessibility" : "standard")")
        for index in 0..<9 {
            let dynamic = height("dynamic.\(index)", app: app)
            let video = height("video.\(index)", app: app)
            XCTAssertEqual(dynamic, video, accuracy: 1, "sample \(index)")
            if !accessibility && index == 1 { XCTAssertEqual(video - off["video.1"]!, 6, accuracy: 1) }
        }
        returnToTop(app)
        _ = height("dynamic.1", app: app)
        app.descendants(matching: .any)["comment.sample.dynamic.1"].press(forDuration: 1)
        XCTAssertTrue(app.buttons["复制评论"].waitForExistence(timeout: 3))
        app.buttons["复制评论"].tap()
        toggle.tap()
        returnToTop(app)
        XCTAssertEqual(height("dynamic.1", app: app), off["dynamic.1"]!, accuracy: 1)
        XCTAssertEqual(height("video.1", app: app), off["video.1"]!, accuracy: 1)
    }
    private func height(_ id: String, app: XCUIApplication) -> Double {
        let metric = app.staticTexts["comment.height.\(id)"]
        for _ in 0..<30 where !metric.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(metric.isHittable, id)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in (Double(metric.label) ?? 0) > 0 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 3), .completed)
        return Double(metric.label) ?? -1
    }
    private func returnToTop(_ app: XCUIApplication) {
        let metric = app.staticTexts["comment.height.dynamic.0"]
        for _ in 0..<30 where !metric.isHittable { app.scrollViews.firstMatch.swipeDown() }
    }
    private func capture(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
