import XCTest

@MainActor
final class DynamicSpacingUITests: XCTestCase {
    func testProductionSpacingAndDetailFullText() {
        verifySpacing(accessibility: false)
    }

    func testSpacingWithAccessibilityDynamicType() {
        verifySpacing(accessibility: true)
    }

    private func verifySpacing(accessibility: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "dynamicSpacing"]
            + (accessibility ? ["--spacing-accessibility"] : [])
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["spacing.detail"].waitForExistence(timeout: 5))

        let firstHeight = height("A", in: app)
        if !accessibility { XCTAssertEqual(firstHeight, 51, accuracy: 1) }
        XCTAssertFalse(app.otherElements["spacing.card.A"].buttons["展开"].exists)
        capture(app, name: "Production-top")
        for id in Array("BCDEFGH").map(String.init) { XCTAssertGreaterThan(height(id, in: app), 0) }
        let collapsed = height("I", in: app)
        let row = app.otherElements["spacing.card.I"]
        XCTAssertTrue(row.buttons["展开"].exists)
        row.buttons["展开"].tap()
        XCTAssertGreaterThan(height("I", in: app), collapsed)
        row.buttons["收起"].tap()
        XCTAssertEqual(height("I", in: app), collapsed, accuracy: 1)
        XCTAssertGreaterThan(height("original", in: app), 0)
        XCTAssertGreaterThan(height("comment", in: app), 0)
        returnToStart(app)
        XCTAssertEqual(height("A", in: app), firstHeight, accuracy: 1)

        app.buttons["spacing.detail"].tap()
        XCTAssertTrue(app.scrollViews["dynamic.detail.scroll"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["展开"].exists)
        XCTAssertFalse(app.buttons["收起"].exists)
        for prefix in ["详情", "原文"] {
            let text = (1...9).map { "\(prefix)第\($0)行全文" }.joined(separator: "\n")
            let body = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", text)).firstMatch
            XCTAssertTrue(body.exists)
            XCTAssertGreaterThan(body.frame.height, accessibility ? 400 : 200)
        }
        capture(app, name: "Detail-full-text")
    }

    private enum Direction { case up, down }

    private func height(_ id: String, in app: XCUIApplication, direction: Direction = .up) -> Double {
        let text = app.staticTexts["spacing.height.\(id)"]
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<35 {
            if text.isHittable { break }
            if direction == .up { scroll.swipeUp() } else { scroll.swipeDown() }
        }
        XCTAssertTrue(text.isHittable, id)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (Double(text.label) ?? 0) > 0
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed, id)
        return Double(text.label) ?? -1
    }

    private func returnToStart(_ app: XCUIApplication) {
        let first = app.staticTexts["spacing.height.A"]
        for _ in 0..<35 {
            if first.isHittable { break }
            app.scrollViews.firstMatch.swipeDown()
        }
        XCTAssertTrue(first.isHittable)
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
