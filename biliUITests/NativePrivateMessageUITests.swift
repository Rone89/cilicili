import XCTest

// Keyboard geometry checks require Simulator “Connect Hardware Keyboard” to be off.
@MainActor
final class NativePrivateMessageUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testExperimentCanReturnToLegacyWithoutLosingDraft() {
        let app = launch([])
        app.buttons["打开私信"].tap()
        let legacy = app.textFields.firstMatch
        XCTAssertTrue(legacy.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["privateMessage.send"].exists)
        legacy.tap(); legacy.typeText("保留草稿")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.switches["privateMessage.fixture.toggle"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.buttons["打开私信"].tap()
        let input = app.descendants(matching: .any)["privateMessage.composer"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(input.value as? String, "保留草稿")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.switches["privateMessage.fixture.toggle"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.buttons["打开私信"].tap()
        XCTAssertTrue(legacy.waitForExistence(timeout: 5))
        XCTAssertEqual(legacy.value as? String, "保留草稿")
        XCTAssertFalse(app.buttons["privateMessage.actions"].exists)
    }

    func testNativeMenusKeyboardAndFailedSendRetry() {
        let app = launch(["--private-message-native", "--private-message-fail-once"])
        app.buttons["打开私信"].tap()
        let send = app.buttons["privateMessage.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        XCTAssertFalse(send.isEnabled)
        let attachments = app.buttons["privateMessage.attachments"]
        XCTAssertEqual(attachments.frame.height, 44, accuracy: 1)
        XCTAssertEqual(attachments.frame.width, 44, accuracy: 1)
        // The plain send button exposes its 30pt symbol, whereas the glass menu exposes its full control.
        XCTAssertEqual(attachments.frame.midY, send.frame.midY, accuracy: 1)
        screenshot(app, "native-private-message-light")
        app.buttons["privateMessage.actions"].tap()
        XCTAssertTrue(app.buttons["个人空间"].waitForExistence(timeout: 3))
        app.buttons["刷新消息"].tap()
        app.buttons["privateMessage.attachments"].tap()
        XCTAssertTrue(app.buttons["照片"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["B站表情"].exists)
        // Tap outside the native menu without selecting a real photo.
        app.navigationBars.firstMatch.tap()
        let input = app.descendants(matching: .any)["privateMessage.composer"].firstMatch
        input.tap()
        waitForKeyboard(app)
        typeHiOnKeyboard(app)
        waitForKeyboard(app)
        XCTAssertTrue(send.isEnabled)
        XCTAssertLessThanOrEqual(send.frame.maxY, app.keyboards.firstMatch.frame.minY + 1)
        screenshot(app, "native-private-message-keyboard")
        send.tap()
        let retry = app.buttons["重试"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, "Hi")
        retry.tap()
        let cleared = NSPredicate { _, _ in !((input.value as? String) ?? "").contains("Hi") }
        expectation(for: cleared, evaluatedWith: input)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.descendants(matching: .any)["Hi"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(retry.exists)
    }

    func testNativeDarkAccessibilityLayout() {
        let app = launch(["--private-message-native", "--private-message-dark", "--private-message-accessibility"])
        app.buttons["打开私信"].tap()
        let input = app.descendants(matching: .any)["privateMessage.composer"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["privateMessage.actions"].isHittable)
        XCTAssertTrue(app.buttons["privateMessage.attachments"].isHittable)
        XCTAssertGreaterThan(input.frame.width, 100)
        input.tap()
        typeHiOnKeyboard(app)
        app.keyboards.buttons["Return"].tap()
        typeHiOnKeyboard(app)
        XCTAssertEqual(input.value as? String, "Hi\nHi")
        XCTAssertTrue(app.buttons["privateMessage.send"].isEnabled)
        waitForKeyboard(app)
        XCTAssertLessThanOrEqual(app.buttons["privateMessage.send"].frame.maxY, app.keyboards.firstMatch.frame.minY + 1)
        screenshot(app, "native-private-message-accessibility-dark")
    }

    private func waitForKeyboard(_ app: XCUIApplication) {
        let visible = NSPredicate { _, _ in
            let keyboard = app.keyboards.firstMatch
            return keyboard.exists && keyboard.frame.minY < app.frame.maxY - 150
                && (keyboard.keys["H"].isHittable || keyboard.keys["h"].isHittable)
        }
        expectation(for: visible, evaluatedWith: app)
        waitForExpectations(timeout: 5)
    }

    // Physical key taps keep the software keyboard visible; typeText may use hardware injection.
    private func typeHiOnKeyboard(_ app: XCUIApplication) {
        waitForKeyboard(app)
        let keyboard = app.keyboards.firstMatch
        let h = keyboard.keys["H"].exists ? keyboard.keys["H"] : keyboard.keys["h"]
        XCTAssertTrue(h.waitForExistence(timeout: 3), keyboard.debugDescription)
        h.tap()
        keyboard.keys["i"].tap()
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "privateMessage", "--ui-test-enable-animations"] + arguments
        app.launch()
        XCTAssertTrue(app.buttons["打开私信"].waitForExistence(timeout: 5))
        return app
    }

    private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
