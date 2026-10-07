import XCTest

@MainActor
final class DynamicSpacingUITests: XCTestCase {
    func testLiveSpacingToggleExpandCollapseAndCommentIsolation() {
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
        XCTAssertTrue(app.descendants(matching: .any)["spacing.toggle"].waitForExistence(timeout: 5))

        let ids = Array("ABCDEFGHI").map(String.init) + ["original", "comment"]
        var off: [String: Double] = [:]
        for id in ids {
            off[id] = height(id, in: app)
            if id == "A" { capture(app, name: "OFF-top-\(accessibility ? "accessibility" : "standard")") }
        }
        XCTAssertFalse(app.otherElements["spacing.card.A"].buttons["展开"].exists)
        capture(app, name: "OFF-\(accessibility ? "accessibility" : "standard")")

        app.descendants(matching: .any)["spacing.toggle"].tap()
        returnToStart(app)
        var on: [String: Double] = [:]
        for id in ids {
            on[id] = height(id, in: app)
            if id == "comment" { XCTAssertEqual(on[id]!, off[id]!, accuracy: 1) }
            else { XCTAssertGreaterThan(on[id]!, off[id]!, id) }
            if id == "A" { capture(app, name: "ON-top-\(accessibility ? "accessibility" : "standard")") }
            if id == "E" { capture(app, name: "ON-emote-\(accessibility ? "accessibility" : "standard")") }
        }
        if !accessibility {
            XCTAssertEqual(on["A"]! - off["A"]!, 6, accuracy: 1)
            // The native Text path uses system font metrics; it must grow without
            // requiring identical outer bounds to the TextKit line-box model.
        }
        capture(app, name: "ON-\(accessibility ? "accessibility" : "standard")")

        _ = height("I", in: app, direction: .down)
        let row = app.otherElements["spacing.card.I"]
        XCTAssertTrue(row.buttons["展开"].exists)
        row.buttons["展开"].tap()
        let expanded = height("I", in: app)
        XCTAssertGreaterThan(expanded, on["I"]!)
        row.buttons["收起"].tap()
        XCTAssertEqual(height("I", in: app), on["I"]!, accuracy: 1)

        app.descendants(matching: .any)["spacing.toggle"].tap()
        returnToStart(app)
        XCTAssertEqual(height("A", in: app), off["A"]!, accuracy: 1)
        XCTAssertFalse(app.otherElements["spacing.card.A"].buttons["展开"].exists)
        // Scroll back through reused rows after disabling the experiment.
        XCTAssertEqual(height("E", in: app), off["E"]!, accuracy: 1)
        XCTAssertEqual(height("I", in: app), off["I"]!, accuracy: 1)
    }

    private enum Direction { case up, down }

    private func height(_ id: String, in app: XCUIApplication, direction: Direction = .up) -> Double {
        let text = app.staticTexts["spacing.height.\(id)"]
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<35 where !text.isHittable {
            if direction == .up { scroll.swipeUp() } else { scroll.swipeDown() }
        }
        XCTAssertTrue(text.isHittable, id)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (Double(text.label) ?? 0) > 0
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 3), .completed, id)
        return Double(text.label) ?? -1
    }

    private func returnToStart(_ app: XCUIApplication) {
        let first = app.staticTexts["spacing.height.A"]
        for _ in 0..<35 where !first.isHittable { app.scrollViews.firstMatch.swipeDown() }
        XCTAssertTrue(first.isHittable)
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
