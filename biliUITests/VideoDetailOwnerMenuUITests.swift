import XCTest

@MainActor
final class VideoDetailOwnerMenuUITests: XCTestCase {
    func testFiveEquidistantButtonsKeepFramesAcrossStyles() {
        let app = launchFixture()
        XCTAssertFalse(app.buttons["video.detail.follow"].exists)
        assertEqualSpacing(app)
        let buttons = [app.buttons["video.detail.ownerMenu"]] + actionButtons(in: app)
        let plainFrames = buttons.map(\.frame)
        toggle("fixture.owner.glass", in: app)
        assertEqualSpacing(app)
        assertMatchingFrames(buttons, expected: plainFrames)
    }

    func testMenuUpdatesFollowingStateAndOpensSpace() {
        let app = launchFixture()
        let menu = app.buttons["video.detail.ownerMenu"]
        XCTAssertEqual(menu.value as? String, "未关注")
        menu.tap()
        let follow = app.buttons["video.detail.ownerMenu.follow"]
        XCTAssertTrue(follow.waitForExistence(timeout: 3))
        XCTAssertEqual(follow.label, "关注")
        tapMenuAction(follow)
        XCTAssertTrue(waitForAccessibilityValue("已关注", on: menu), app.debugDescription)
        menu.tap()
        XCTAssertTrue(waitForAccessibilityLabel("已关注", on: follow), app.debugDescription)
        tapMenuAction(follow)
        XCTAssertTrue(waitForAccessibilityValue("未关注", on: menu), app.debugDescription)
        menu.tap()
        tapMenuAction(app.buttons["video.detail.ownerMenu.space"])
        XCTAssertTrue(app.staticTexts["fixture.owner.space"].waitForExistence(timeout: 3))
    }

    func testFollowActionDisabledDuringMutation() {
        let app = launchFixture()
        toggle("fixture.owner.mutating", in: app)
        app.buttons["video.detail.ownerMenu"].tap()
        let follow = app.buttons["video.detail.ownerMenu.follow"]
        XCTAssertTrue(follow.waitForExistence(timeout: 3))
        XCTAssertFalse(follow.isEnabled)
        tapMenuAction(app.buttons["video.detail.ownerMenu.space"])
        XCTAssertTrue(app.staticTexts["fixture.owner.space"].waitForExistence(timeout: 3))
    }

    func testMissingOwnerKeepsOtherActionsAvailable() {
        let app = launchFixture()
        toggle("fixture.owner.available", in: app)
        XCTAssertFalse(app.buttons["video.detail.ownerMenu"].exists)
        for button in actionButtons(in: app) {
            XCTAssertTrue(button.exists)
            XCTAssertTrue(button.isEnabled)
        }
    }

    private func tapMenuAction(_ action: XCUIElement) {
        let button = action.firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertTrue(button.isEnabled)
        XCTAssertGreaterThan(button.frame.width, 0)
        XCTAssertGreaterThan(button.frame.height, 0)
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func launchFixture() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "videoOwnerMenu", "--ui-test-enable-animations"]
        app.launch()
        XCTAssertTrue(app.buttons["video.detail.ownerMenu"].waitForExistence(timeout: 5))
        addTeardownBlock { app.terminate() }
        return app
    }

    private func toggle(_ id: String, in app: XCUIApplication) {
        let element = app.switches[id]
        let previousValue = element.value as? String
        // SwiftUI exposes both the row and its native switch; tap the trailing control.
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertNotEqual(element.value as? String, previousValue)
    }

    private func actionButtons(in app: XCUIApplication) -> [XCUIElement] {
        ["like", "coin", "favorite", "more"].map { app.buttons["video.detail.\($0)"] }
    }

    private func waitForAccessibilityValue(_ value: String, on element: XCUIElement) -> Bool {
        let updated = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", value),
            object: element
        )
        return XCTWaiter.wait(for: [updated], timeout: 5) == .completed
    }

    private func waitForAccessibilityLabel(_ label: String, on element: XCUIElement) -> Bool {
        let updated = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", label),
            object: element
        )
        return XCTWaiter.wait(for: [updated], timeout: 5) == .completed
    }

    private func assertMatchingFrames(_ buttons: [XCUIElement], expected: [CGRect]) {
        for (button, frame) in zip(buttons, expected) {
            XCTAssertEqual(button.frame.midX, frame.midX, accuracy: 1, button.identifier)
            XCTAssertEqual(button.frame.midY, frame.midY, accuracy: 1, button.identifier)
            XCTAssertEqual(button.frame.width, frame.width, accuracy: 1, button.identifier)
            XCTAssertEqual(button.frame.height, frame.height, accuracy: 1, button.identifier)
        }
    }

    private func assertEqualSpacing(_ app: XCUIApplication) {
        let ids = ["ownerMenu", "like", "coin", "favorite", "more"]
        let centers = ids.map { app.buttons["video.detail.\($0)"].frame.midX }
        let expectedGap = centers[1] - centers[0]
        XCTAssertGreaterThan(expectedGap, 0)
        for i in 1..<centers.count {
            XCTAssertEqual(centers[i] - centers[i - 1], expectedGap, accuracy: 2)
        }
    }
}
