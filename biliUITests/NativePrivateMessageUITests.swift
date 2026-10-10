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
        XCTAssertEqual(attachments.frame.height, 48, accuracy: 1)
        XCTAssertEqual(attachments.frame.width, 48, accuracy: 1)
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
        // Empty space in the message area dismisses the keyboard without discarding the draft.
        let messageArea = app.scrollViews["privateMessage.messages"]
        XCTAssertTrue(messageArea.exists, app.debugDescription)
        messageArea.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        let dismissed = NSPredicate { _, _ in
            !app.keyboards.firstMatch.exists || app.keyboards.firstMatch.frame.minY >= app.frame.maxY - 150
        }
        let hiddenKeyboard = XCTNSPredicateExpectation(predicate: dismissed, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [hiddenKeyboard], timeout: 5), .completed, app.debugDescription)
        XCTAssertEqual(input.value as? String, "Hi")
        input.tap()
        waitForKeyboard(app)
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

    func testNativeToolbarComposerFollowsKeyboardAndGrows() {
        let app = launch(["--private-message-native"])
        app.buttons["打开私信"].tap()
        let send = app.buttons["privateMessage.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        let input = app.descendants(matching: .any)["privateMessage.composer"].firstMatch
        let attachments = app.buttons["privateMessage.attachments"]
        XCTAssertEqual(attachments.frame.midY, send.frame.midY, accuracy: 1)
        let container = app.descendants(matching: .any)["privateMessage.inputContainer"].firstMatch
        XCTAssertTrue(container.exists)
        XCTAssertEqual(container.frame.height, 48, accuracy: 1)
        XCTAssertEqual(attachments.frame.height, container.frame.height, accuracy: 1)
        screenshot(app, "native-private-message-toolbar-keyboard-closed")
        input.tap()
        waitForKeyboard(app)
        let singleLineHeight = input.frame.height
        input.typeText("one\ntwo\nthree")
        input.tap()
        waitForKeyboard(app)
        XCTAssertEqual(input.value as? String, "one\ntwo\nthree")
        XCTAssertGreaterThan(input.frame.height, singleLineHeight)
        XCTAssertTrue(send.isHittable)
        XCTAssertLessThanOrEqual(send.frame.maxY, app.keyboards.firstMatch.frame.minY + 1)
        XCTAssertEqual(attachments.frame.midY, send.frame.midY, accuracy: 1)
        XCTAssertLessThanOrEqual(attachments.frame.maxY, app.keyboards.firstMatch.frame.minY + 1)
        screenshot(app, "native-private-message-toolbar-multiline")
    }

    func testNativeShortConversationStaysTopAligned() {
        let app = launch(["--private-message-native"])
        app.buttons["打开私信"].tap()
        XCTAssertTrue(app.buttons["privateMessage.send"].waitForExistence(timeout: 5))
        let messageArea = app.scrollViews["privateMessage.messages"]
        let firstMessage = app.descendants(matching: .any)["你好，这是第一条消息。"].firstMatch
        XCTAssertTrue(messageArea.exists)
        XCTAssertTrue(firstMessage.waitForExistence(timeout: 5))
        XCTAssertLessThan(
            firstMessage.frame.minY - messageArea.frame.minY,
            messageArea.frame.height * 0.3
        )
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

    func testDiagonalBackSwipeDoesNotRefreshMessages() {
        let app = launch(["--private-message-native"])
        app.buttons["打开私信"].tap()
        XCTAssertTrue(app.buttons["privateMessage.send"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["你好，这是第一条消息。"].firstMatch.waitForExistence(timeout: 5))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.30))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.52))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(app.buttons["打开私信"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(app.staticTexts["privateMessage.fixture.requests"].value as? String, "1")
    }

    func testProductionNavigationChainBackAndCancelledBack() {
        let app = launch(["--private-message-native", "--private-message-navigation-chain"])
        app.buttons["打开通知"].tap()
        app.buttons["私信"].tap()
        let contact = app.buttons.containing(.staticText, identifier: "测试联系人").firstMatch
        XCTAssertTrue(contact.waitForExistence(timeout: 5), app.debugDescription)
        contact.tap()
        XCTAssertTrue(app.buttons["privateMessage.send"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["你好，这是第一条消息。"].firstMatch.waitForExistence(timeout: 5))
        let header = app.descendants(matching: .any)["privateMessage.header"].firstMatch
        XCTAssertTrue(header.exists, app.debugDescription)
        XCTAssertEqual(header.frame.height, 44, accuracy: 1)
        screenshot(app, "native-private-message-44pt-header")
        // A slow, short interactive pop cancels and must leave the conversation usable.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.30))
        start.press(forDuration: 0.05,
                    thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.28, dy: 0.36)),
                    withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertTrue(app.buttons["privateMessage.send"].waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertFalse(app.activityIndicators.firstMatch.isHittable, app.debugDescription)
        // Full-width diagonal back through the same bridge used by the root destination.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.30))
            .press(forDuration: 0.05,
                   thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.52)))
        XCTAssertTrue(contact.waitForExistence(timeout: 5), app.debugDescription)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["打开通知"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["privateMessage.fixture.requests"].value as? String, "1")
        XCTAssertEqual(app.staticTexts["privateMessage.fixture.refreshActions"].value as? String, "0")
        let suspensions = Int(app.staticTexts["privateMessage.fixture.refreshSuspensions"].value as? String ?? "")
        XCTAssertGreaterThanOrEqual(suspensions ?? 0, 1, "The production message refresh control must be protected during pop")
    }

    func testProductionNavigationChainVerticalPullSubmitsRefresh() {
        let app = launch(["--private-message-native", "--private-message-navigation-chain"])
        app.buttons["打开通知"].tap()
        app.buttons["私信"].tap()
        let contact = app.buttons.containing(.staticText, identifier: "测试联系人").firstMatch
        XCTAssertTrue(contact.waitForExistence(timeout: 5))
        contact.tap()
        XCTAssertTrue(app.buttons["privateMessage.send"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["你好，这是第一条消息。"].firstMatch.waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.23))
            .press(forDuration: 0.05,
                   thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.75)),
                   withVelocity: .slow, thenHoldForDuration: 0.3)
        // Navigating back immediately may cancel the request; the vertical gesture must still submit the refresh action.
        XCTAssertTrue(app.buttons["privateMessage.send"].exists)
        for _ in 0..<3 { app.navigationBars.buttons.element(boundBy: 0).tap() }
        XCTAssertTrue(app.buttons["打开通知"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["privateMessage.fixture.refreshActions"].value as? String, "1")
    }

    func testVerticalScrollingAndRefreshMenuRemainAvailable() {
        let app = launch(["--private-message-native", "--private-message-refresh-marker", "--private-message-long-history"], animations: false)
        app.buttons["打开私信"].tap()
        XCTAssertTrue(app.buttons["privateMessage.send"].waitForExistence(timeout: 5))
        let firstMessage = app.descendants(matching: .any)["你好，这是第一条消息。"].firstMatch
        XCTAssertTrue(firstMessage.waitForExistence(timeout: 5))
        let initialY = firstMessage.frame.minY
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.90, dy: 0.22))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.90, dy: 0.65))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertGreaterThan(firstMessage.frame.minY, initialY)
        XCTAssertTrue(app.buttons["privateMessage.send"].exists)
        app.buttons["privateMessage.actions"].tap()
        app.buttons["刷新消息"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["消息刷新已完成"].firstMatch.waitForExistence(timeout: 3), app.debugDescription)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["打开私信"].waitForExistence(timeout: 3))
        let requests = Int(app.staticTexts["privateMessage.fixture.requests"].value as? String ?? "")
        XCTAssertGreaterThanOrEqual(requests ?? 0, 2)
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

    private func launch(_ arguments: [String], animations: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "privateMessage"]
            + (animations ? ["--ui-test-enable-animations"] : []) + arguments
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
