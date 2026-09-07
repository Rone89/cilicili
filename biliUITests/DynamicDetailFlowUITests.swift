import XCTest

final class DynamicDetailFlowUITests: XCTestCase {
    @MainActor
    func testTelegramInputStyleInteractionBarGeometry() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-fixture", "dynamicDetail",
            "--ui-test-reset-state",
            "--ui-test-root-tab-shell",
            "--ui-test-dynamic-bottom-interaction-bar",
            "--ui-test-telegram-input-style"
        ]
        app.launch()
        let content = app.staticTexts["图文动态测试内容"]
        XCTAssertTrue(content.waitForExistence(timeout: 5))
        content.tap()

        let share = app.buttons["dynamic.detail.composer.share"]
        let comment = app.buttons["dynamic.detail.composer.comment"]
        let like = app.buttons["dynamic.detail.composer.like"]
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        XCTAssertTrue(comment.exists)
        XCTAssertTrue(like.exists)

        let window = app.windows.firstMatch.frame
        XCTAssertEqual(share.frame.width, 44, accuracy: 1)
        XCTAssertEqual(like.frame.width, 44, accuracy: 1)
        XCTAssertEqual(comment.frame.height, 40, accuracy: 1)
        XCTAssertEqual(share.frame.minX - window.minX, 24, accuracy: 1)
        XCTAssertEqual(window.maxX - like.frame.maxX, 24, accuracy: 1)
        XCTAssertEqual(window.maxY - share.frame.maxY, 28, accuracy: 1)
        XCTAssertEqual(share.frame.minY, like.frame.minY, accuracy: 1)

        comment.tap()
        let editor = app.descendants(matching: .any)["dynamic.detail.composer.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3))
        let keyboardSettled = NSPredicate { _, _ in
            keyboard.exists && keyboard.frame.minY < window.maxY - 100
                && abs(keyboard.frame.maxY - window.maxY) < 2
        }
        let keyboardReady = XCTWaiter.wait(
            for: [expectation(for: keyboardSettled, evaluatedWith: nil)],
            timeout: 5
        )
        guard keyboardReady == .completed else {
            throw XCTSkip("Show the simulator software keyboard before running the keyboard/panel geometry test.")
        }
        XCTAssertTrue(share.exists)
        XCTAssertTrue(like.exists)
        XCTAssertEqual(share.frame.width, 44, accuracy: 1)
        XCTAssertEqual(like.frame.width, 44, accuracy: 1)
        XCTAssertGreaterThan(editor.frame.height, 0)
        XCTAssertLessThanOrEqual(editor.frame.maxY, keyboard.frame.minY + 1)
        XCTAssertEqual(share.frame.minX - window.minX, 24, accuracy: 1)
        XCTAssertEqual(window.maxX - like.frame.maxX, 24, accuracy: 1)
        XCTAssertEqual(share.frame.minY, like.frame.minY, accuracy: 1)
        XCTAssertLessThanOrEqual(share.frame.maxY, keyboard.frame.minY + 1)
        let keyboardFrame = keyboard.frame
        let keyboardBarFrame = share.frame
        let keyboardAttachment = XCTAttachment(screenshot: app.screenshot())
        keyboardAttachment.name = "Keyboard layout"
        keyboardAttachment.lifetime = .keepAlways
        add(keyboardAttachment)
        app.buttons["选择表情"].tap()
        let emotePicker = app.scrollViews["dynamic.comment.emotePicker"]
        XCTAssertTrue(emotePicker.waitForExistence(timeout: 3))
        XCTAssertEqual(emotePicker.frame.minX, window.minX, accuracy: 1)
        XCTAssertEqual(emotePicker.frame.width, window.width, accuracy: 1)
        let panelAttachment = XCTAttachment(screenshot: app.screenshot())
        panelAttachment.name = "Emote panel layout"
        panelAttachment.lifetime = .keepAlways
        add(panelAttachment)
        print("LAYOUT window=\(window) keyboard=\(keyboardFrame) barBefore=\(keyboardBarFrame) panel=\(emotePicker.frame) barAfter=\(share.frame)")
        XCTAssertEqual(emotePicker.frame.minY, keyboardFrame.minY, accuracy: 2)
        XCTAssertEqual(emotePicker.frame.maxY, window.maxY, accuracy: 2)
        XCTAssertEqual(share.frame.minY, keyboardBarFrame.minY, accuracy: 2)
        XCTAssertEqual(emotePicker.frame.minY - share.frame.maxY, keyboardFrame.minY - keyboardBarFrame.maxY, accuracy: 2)
        XCTAssertFalse(app.buttons["切换至键盘"].exists)
    }

    @MainActor
    func testTappingEditorAfterEmotePanelRestoresSystemKeyboard() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-fixture", "dynamicDetail",
            "--ui-test-reset-state",
            "--ui-test-root-tab-shell",
            "--ui-test-dynamic-bottom-interaction-bar",
            "--ui-test-telegram-input-style"
        ]
        app.launch()

        let content = app.staticTexts["图文动态测试内容"]
        XCTAssertTrue(content.waitForExistence(timeout: 5))
        content.tap()

        let comment = app.buttons["dynamic.detail.composer.comment"]
        XCTAssertTrue(comment.waitForExistence(timeout: 5))
        comment.tap()

        let editor = app.descendants(matching: .any)["dynamic.detail.composer.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))

        let emoteButton = app.buttons["选择表情"]
        XCTAssertTrue(emoteButton.waitForExistence(timeout: 3))
        emoteButton.tap()

        let closeEmotePicker = app.buttons["收起表情选择器"]
        XCTAssertTrue(closeEmotePicker.waitForExistence(timeout: 3))
        let panel = app.descendants(matching: .any)["dynamic.comment.emotePicker"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(panel.frame.height, 200)

        editor.tap()

        let systemKeyboard = app.keyboards.firstMatch
        let keyboardRaised = NSPredicate { _, _ in
            systemKeyboard.exists
                && systemKeyboard.frame.minY < app.windows.firstMatch.frame.maxY - 100
        }
        let keyboardReady = XCTWaiter.wait(
            for: [expectation(for: keyboardRaised, evaluatedWith: nil)],
            timeout: 5
        )
        XCTAssertEqual(keyboardReady, .completed)
        XCTAssertTrue(app.buttons["选择表情"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testTappingComposerEditorExplicitlyRestoresFocus() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-fixture", "dynamicDetail",
            "--ui-test-reset-state",
            "--ui-test-root-tab-shell",
            "--ui-test-dynamic-bottom-interaction-bar",
            "--ui-test-telegram-input-style"
        ]
        app.launch()

        app.staticTexts["图文动态测试内容"].tap()
        let comment = app.buttons["dynamic.detail.composer.comment"]
        XCTAssertTrue(comment.waitForExistence(timeout: 5))
        comment.tap()

        let editor = app.descendants(matching: .any)["dynamic.detail.composer.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3))

        let photoButton = app.buttons["添加图片"]
        XCTAssertTrue(photoButton.waitForExistence(timeout: 3))
        photoButton.tap()
        XCTAssertTrue(app.buttons["收起照片选择器"].waitForExistence(timeout: 3))
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 3))

        editor.tap()

        XCTAssertTrue(keyboard.waitForExistence(timeout: 3))
        editor.typeText("keyboard")
        XCTAssertEqual(editor.value as? String, "keyboard")
    }

    @MainActor
    func testRichCommentComposerUsesNativeTextEditorAndEmoteInputView() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-fixture", "dynamicDetail",
            "--ui-test-reset-state",
            "--ui-test-root-tab-shell",
            "--ui-test-rich-comment-composer"
        ]
        app.launch()

        app.staticTexts["图文动态测试内容"].tap()
        let comment = app.buttons["dynamic.detail.composer.comment"]
        XCTAssertTrue(comment.waitForExistence(timeout: 5))
        comment.tap()

        let editor = app.textViews["dynamic.comment.composer.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertFalse(app.sheets.firstMatch.exists)
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3))
        let window = app.windows.firstMatch.frame
        let keyboardFrame = keyboard.frame
        editor.typeText("native")
        XCTAssertEqual(editor.value as? String, "native")

        let keyboardScreenshot = XCTAttachment(screenshot: app.screenshot())
        keyboardScreenshot.name = "Rich composer with system keyboard"
        keyboardScreenshot.lifetime = .keepAlways
        add(keyboardScreenshot)

        let emoteButton = app.buttons["dynamic.comment.composer.emote"]
        XCTAssertTrue(emoteButton.waitForExistence(timeout: 3))
        emoteButton.tap()
        let emotePicker = app.descendants(matching: .any)["dynamic.comment.emotePicker"].firstMatch
        XCTAssertTrue(emotePicker.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(emotePicker.frame.height, 200)
        let emoteScreenshot = XCTAttachment(screenshot: app.screenshot())
        emoteScreenshot.name = "Rich composer with emote input view"
        emoteScreenshot.lifetime = .keepAlways
        add(emoteScreenshot)
        print("RICH_LAYOUT window=\(window) keyboard=\(keyboardFrame) editor=\(editor.frame) panel=\(emotePicker.frame)")
        XCTAssertGreaterThan(emotePicker.frame.minY, window.minY + window.height * 0.25)
        XCTAssertLessThan(emotePicker.frame.height, window.height * 0.75)
        XCTAssertGreaterThanOrEqual(emotePicker.frame.height, keyboardFrame.height)
        XCTAssertEqual(emotePicker.frame.maxY, window.maxY, accuracy: 2)
        XCTAssertEqual(editor.value as? String, "native")
    }

    @MainActor
    func testRichCommentComposerPhotoPickerSelectionAndRemoval() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-fixture", "dynamicDetail",
            "--ui-test-reset-state",
            "--ui-test-root-tab-shell",
            "--ui-test-rich-comment-composer"
        ]
        app.launch()
        app.staticTexts["图文动态测试内容"].tap()
        let comment = app.buttons["dynamic.detail.composer.comment"]
        XCTAssertTrue(comment.waitForExistence(timeout: 5))
        comment.tap()
        let editor = app.textViews["dynamic.comment.composer.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        let photoButton = app.buttons["添加图片"]
        XCTAssertTrue(photoButton.waitForExistence(timeout: 3))
        photoButton.tap()
        sleep(2)

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.13, dy: 0.35)).tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.90, dy: 0.15)).tap()
        sleep(2)

        let attachments = app.descendants(matching: .any)[
            "dynamic.comment.composer.attachments"
        ].firstMatch
        XCTAssertTrue(attachments.waitForExistence(timeout: 10))
        let removeButton = app.buttons["dynamic.comment.composer.removeImage"].firstMatch
        XCTAssertTrue(removeButton.waitForExistence(timeout: 3))
        removeButton.tap()
        XCTAssertTrue(attachments.waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testRichCommentComposerDismissesOnOutsideTap() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-fixture", "dynamicDetail",
            "--ui-test-reset-state",
            "--ui-test-root-tab-shell",
            "--ui-test-rich-comment-composer"
        ]
        app.launch()
        app.staticTexts["图文动态测试内容"].tap()

        let comment = app.buttons["dynamic.detail.composer.comment"]
        XCTAssertTrue(comment.waitForExistence(timeout: 5))
        comment.tap()

        let editor = app.textViews["dynamic.comment.composer.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        let outside = app.windows.firstMatch.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)
        )
        outside.tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testComposerCompactControlGeometry() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-fixture", "dynamicDetail",
            "--ui-test-reset-state",
            "--ui-test-root-tab-shell",
            "--ui-test-dynamic-composer"
        ]
        app.launch()
        let content = app.staticTexts["图文动态测试内容"]
        XCTAssertTrue(content.waitForExistence(timeout: 5))
        content.tap()

        let comment = app.buttons["发表评论"]
        XCTAssertTrue(comment.waitForExistence(timeout: 5))
        let like = app.buttons["dynamic.detail.composer.like"]
        let favorite = app.buttons["dynamic.detail.composer.favorite"]
        XCTAssertTrue(like.exists)
        XCTAssertTrue(favorite.exists)
        let window = app.windows.firstMatch.frame
        let likeSurface = like.frame.insetBy(dx: 2, dy: 2)
        let favoriteSurface = favorite.frame.insetBy(dx: 2, dy: 2)
        XCTAssertEqual(like.frame.width, 44, accuracy: 1)
        XCTAssertEqual(favorite.frame.width, 44, accuracy: 1)
        XCTAssertEqual(likeSurface.height, 40, accuracy: 1)
        XCTAssertEqual(favoriteSurface.height, 40, accuracy: 1)
        XCTAssertEqual(comment.frame.height, 40, accuracy: 1)
        XCTAssertEqual(likeSurface.minX - window.minX, 26, accuracy: 1)
        XCTAssertEqual(window.maxX - favoriteSurface.maxX, 26, accuracy: 1)
        XCTAssertEqual(window.maxY - comment.frame.maxY, 28, accuracy: 1)
        XCTAssertEqual(comment.frame.minX - likeSurface.maxX, 6, accuracy: 1)
        XCTAssertEqual(favoriteSurface.minX - comment.frame.maxX, 6, accuracy: 1)
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testImageTextDynamicOpensNativeDetail() {
        let app = launchDynamicDetailFixture()

        let content = app.staticTexts["图文动态测试内容"]
        XCTAssertTrue(content.waitForExistence(timeout: 5))
        content.tap()

        let detailScroll = app.scrollViews["dynamic.detail.scroll"]
        XCTAssertTrue(detailScroll.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["图文动态测试内容"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["dynamic.detail.inlineComments"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["dynamic.detail.bottomActionBar"].exists)
        XCTAssertTrue(app.buttons["评论回复"].exists)

        let navigationBar = app.navigationBars.firstMatch
        let navigationTitle = app.staticTexts["动态详情"]
        let backButton = navigationBar.buttons.firstMatch
        XCTAssertTrue(navigationBar.exists)
        XCTAssertTrue(navigationTitle.exists)
        XCTAssertTrue(backButton.exists)
        XCTAssertEqual(
            navigationTitle.frame.midX,
            app.windows.firstMatch.frame.midX,
            accuracy: 1,
            "动态详情标题应相对屏幕居中"
        )
        let initialTitleFrame = navigationTitle.frame
        let initialBackButtonFrame = backButton.frame
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertEqual(navigationTitle.frame.midX, initialTitleFrame.midX, accuracy: 1)
        XCTAssertEqual(navigationTitle.frame.midY, initialTitleFrame.midY, accuracy: 1)
        XCTAssertEqual(backButton.frame.midX, initialBackButtonFrame.midX, accuracy: 1)
        XCTAssertEqual(backButton.frame.midY, initialBackButtonFrame.midY, accuracy: 1)

        app.scrollViews["dynamic.detail.scroll"].swipeUp()
        let titleHiddenDeadline = Date().addingTimeInterval(1)
        while navigationTitle.isHittable && Date() < titleHiddenDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertFalse(navigationTitle.isHittable)
        XCTAssertTrue(backButton.exists)
    }

    @MainActor
    func testAnimatedRootTabShellPushKeepsNativeNavigationStable() {
        assertAnimatedRootPushKeepsNativeNavigationStable()
    }

    @MainActor
    func testAnimatedRootTabShellUploaderPushKeepsBackButtonStable() {
        let app = launchDynamicDetailFixture(
            enablesAnimations: true,
            usesRootTabShell: true
        )

        let openUploaderButton = app.buttons["fixture.dynamic.openUploader"]
        XCTAssertTrue(openUploaderButton.waitForExistence(timeout: 5))
        openUploaderButton.tap()

        let uploaderRoot = app.descendants(matching: .any)["fixture.uploader.root"]
        let navigationBar = app.navigationBars.firstMatch
        let backButton = navigationBar.buttons.firstMatch
        XCTAssertTrue(uploaderRoot.waitForExistence(timeout: 3))
        XCTAssertTrue(backButton.waitForExistence(timeout: 3))
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        XCTAssertFalse(navigationBar.staticTexts["动态"].exists)

        let initialBackButtonFrame = backButton.frame
        for _ in 0..<10 {
            Thread.sleep(forTimeInterval: 0.1)
            XCTAssertEqual(backButton.frame.midX, initialBackButtonFrame.midX, accuracy: 0.5)
            XCTAssertEqual(backButton.frame.midY, initialBackButtonFrame.midY, accuracy: 0.5)
        }
    }

    @MainActor
    private func assertAnimatedRootPushKeepsNativeNavigationStable() {
        let app = launchDynamicDetailFixture(
            enablesAnimations: true,
            usesRootTabShell: true
        )

        let content = app.staticTexts["图文动态测试内容"]
        XCTAssertTrue(content.waitForExistence(timeout: 5))
        content.tap()

        XCTAssertTrue(app.scrollViews["dynamic.detail.scroll"].waitForExistence(timeout: 3))
        let navigationBar = app.navigationBars.firstMatch
        let backButton = navigationBar.buttons.firstMatch
        let navigationTitle = app.staticTexts["动态详情"]
        XCTAssertTrue(backButton.exists)
        XCTAssertTrue(navigationTitle.exists)
        XCTAssertFalse(app.tabBars.firstMatch.exists)

        var pushBackButtonFrames = [CGRect]()
        var pushTitleFrames = [CGRect]()
        for _ in 0..<8 {
            if backButton.exists, navigationTitle.exists {
                pushBackButtonFrames.append(backButton.frame)
                pushTitleFrames.append(navigationTitle.frame)
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertFalse(pushBackButtonFrames.isEmpty)
        XCTAssertFalse(pushTitleFrames.isEmpty)
        guard let lastPushBackButtonFrame = pushBackButtonFrames.last,
              let lastPushTitleFrame = pushTitleFrames.last
        else {
            return
        }

        let settledBackButtonFrame = backButton.frame
        let settledTitleFrame = navigationTitle.frame
        for _ in 0..<8 {
            Thread.sleep(forTimeInterval: 0.1)
            XCTAssertEqual(backButton.frame.midX, settledBackButtonFrame.midX, accuracy: 0.5)
            XCTAssertEqual(backButton.frame.midY, settledBackButtonFrame.midY, accuracy: 0.5)
            XCTAssertEqual(navigationTitle.frame.midX, settledTitleFrame.midX, accuracy: 0.5)
            XCTAssertEqual(navigationTitle.frame.midY, settledTitleFrame.midY, accuracy: 0.5)
        }
        XCTAssertEqual(
            navigationTitle.frame.midX,
            app.windows.firstMatch.frame.midX,
            accuracy: 0.5,
            "动态详情标题应相对屏幕居中"
        )
        XCTAssertEqual(
            lastPushBackButtonFrame.midX,
            settledBackButtonFrame.midX,
            accuracy: 0.5,
            "Push 完成后返回按钮不应发生二次横向对齐"
        )
        XCTAssertEqual(
            lastPushTitleFrame.midX,
            settledTitleFrame.midX,
            accuracy: 0.5,
            "Push 完成后详情标题不应发生二次横向对齐"
        )
    }

    @MainActor
    func testRootTabShellShowsHomeToolbarItems() {
        let app = launchDynamicDetailFixture(
            usesRootTabShell: true
        )
        XCTAssertTrue(app.tabBars.buttons["首页"].waitForExistence(timeout: 5))
        app.tabBars.buttons["首页"].tap()

        XCTAssertTrue(app.buttons["fixture.home.mode"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["fixture.home.messages"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testHomeNavigationBarMinimizesOnScrollDown() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-reset-state",
            "--start-tab", "home",
        ]
        app.launch()

        let modeButton = app.buttons["首页内容"]
        let messageButton = app.buttons["账号消息"]
        let scrollView = app.scrollViews.firstMatch
        XCTAssertTrue(modeButton.waitForExistence(timeout: 5))
        XCTAssertTrue(messageButton.waitForExistence(timeout: 5))
        XCTAssertTrue(scrollView.waitForExistence(timeout: 5))

        scrollView.swipeUp()

        XCTAssertTrue(waitForHittableState(false, element: modeButton, timeout: 3))
        XCTAssertTrue(waitForHittableState(false, element: messageButton, timeout: 3))
        XCTAssertTrue(app.tabBars.firstMatch.exists)

        for _ in 0..<4 where !modeButton.isHittable {
            scrollView.swipeDown()
        }

        XCTAssertTrue(waitForHittableState(true, element: modeButton, timeout: 3))
    }

    @MainActor
    func testImageTextDynamicThumbnailOpensImageViewer() {
        let app = launchDynamicDetailFixture()

        let thumbnail = app.buttons["查看第 1 张图片，共 8 张"]
        XCTAssertTrue(thumbnail.waitForExistence(timeout: 5))
        thumbnail.tap()

        XCTAssertTrue(app.descendants(matching: .any)["图片预览"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.scrollViews["dynamic.detail.scroll"].exists)
    }

    @MainActor
    func testCommentButtonKeepsSheetWithoutOpeningDetail() {
        let app = launchDynamicDetailFixture()

        let commentButton = app.buttons["2"]
        XCTAssertTrue(commentButton.waitForExistence(timeout: 5))
        commentButton.tap()

        let commentsScroll = app.scrollViews["dynamic.comments.scroll"]
        XCTAssertTrue(commentsScroll.waitForExistence(timeout: 3))
        XCTAssertFalse(app.scrollViews["dynamic.detail.scroll"].exists)
        XCTAssertTrue(commentsScroll.exists)
    }

    @MainActor
    func testPureTextExpandedContentAreaOpensNativeDetail() {
        let app = launchDynamicDetailFixture()
        app.scrollViews.firstMatch.swipeUp()
        let detailTapArea = app.buttons["dynamic.feed.detailTapArea.223456789.content"]
        scrollToElement(detailTapArea, in: app)

        detailTapArea.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()

        XCTAssertTrue(app.scrollViews["dynamic.detail.scroll"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["纯文本动态测试内容"].exists)
    }

    @MainActor
    func testForwardDynamicOpensNativeDetail() {
        let app = launchDynamicDetailFixture()
        let content = app.staticTexts["转发动态测试内容"]
        scrollToElement(content, in: app)

        content.tap()

        XCTAssertTrue(app.scrollViews["dynamic.detail.scroll"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["被转发的原动态内容"].exists)
    }

    @MainActor
    func testForwardOriginalContentOpensOriginalDetailRoute() {
        let app = launchDynamicDetailFixture()
        let originalTapArea = app.buttons[
            "dynamic.feed.originalDetailTapArea.323456789.423456789"
        ]
        scrollToElement(originalTapArea, in: app)

        originalTapArea.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()

        XCTAssertTrue(app.scrollViews["dynamic.detail.scroll"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["转发动态测试内容"].exists)
    }

    @MainActor
    func testReturningFromForwardedContentStaysOnForwardDetail() {
        let app = launchDynamicDetailFixture()
        let forwardContent = app.staticTexts["转发动态测试内容"]
        scrollToElement(forwardContent, in: app)
        forwardContent.tap()

        XCTAssertTrue(app.scrollViews["dynamic.detail.scroll"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["转发动态测试内容"].exists)

        let originalTapArea = app.buttons[
            "dynamic.feed.originalDetailTapArea.323456789.423456789"
        ]
        scrollToElement(originalTapArea, in: app)
        originalTapArea.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()

        XCTAssertFalse(app.staticTexts["转发动态测试内容"].exists)
        let backButton = app.navigationBars.firstMatch.buttons.firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: 3))
        backButton.tap()

        XCTAssertTrue(app.scrollViews["dynamic.detail.scroll"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["转发动态测试内容"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testRootTabShellContentSwipeReturnsToDynamicFeed() {
        let app = launchDynamicDetailFixture(
            usesRootTabShell: true
        )
        let content = app.staticTexts["图文动态测试内容"]
        XCTAssertTrue(content.waitForExistence(timeout: 5))
        content.tap()

        let detailScroll = app.scrollViews["dynamic.detail.scroll"]
        XCTAssertTrue(detailScroll.waitForExistence(timeout: 3))
        XCTAssertTrue(app.navigationBars.firstMatch.buttons.firstMatch.exists)

        app.swipeRight()

        XCTAssertFalse(detailScroll.waitForExistence(timeout: 1))
        XCTAssertTrue(app.staticTexts["图文动态测试内容"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testRootTabShellRestoresTabBarAfterPop() {
        let app = launchDynamicDetailFixture(
            usesRootTabShell: true
        )
        let content = app.staticTexts["图文动态测试内容"]
        XCTAssertTrue(content.waitForExistence(timeout: 5))
        content.tap()

        XCTAssertTrue(app.scrollViews["dynamic.detail.scroll"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.tabBars.firstMatch.exists)

        app.navigationBars.firstMatch.buttons.firstMatch.tap()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(content.waitForExistence(timeout: 3))
    }

    @MainActor
    func testAnimatedRootTabBarRestoresAfterPop() {
        let app = launchDynamicDetailFixture(
            enablesAnimations: true,
            usesRootTabShell: true
        )
        let content = app.staticTexts["图文动态测试内容"]
        XCTAssertTrue(content.waitForExistence(timeout: 5))
        content.tap()

        XCTAssertTrue(app.scrollViews["dynamic.detail.scroll"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.tabBars.firstMatch.exists)

        app.navigationBars.firstMatch.buttons.firstMatch.tap()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(content.waitForExistence(timeout: 3))
    }

    @MainActor
    func testAnimatedRootTabBarRestoresAfterUploaderPop() {
        let app = launchDynamicDetailFixture(
            enablesAnimations: true,
            usesRootTabShell: true
        )
        let openUploaderButton = app.buttons["fixture.dynamic.openUploader"]
        XCTAssertTrue(openUploaderButton.waitForExistence(timeout: 5))
        openUploaderButton.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["fixture.uploader.root"].waitForExistence(timeout: 3)
        )
        XCTAssertFalse(app.tabBars.firstMatch.exists)

        app.navigationBars.firstMatch.buttons.firstMatch.tap()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(openUploaderButton.waitForExistence(timeout: 3))
    }

    @MainActor
    func testProductionRootNavigationRestoresTabBarWithBackButton() {
        let app = launchProductionUploader()
        let backButton = app.navigationBars.firstMatch.buttons.firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: 10))
        XCTAssertFalse(app.tabBars.firstMatch.exists)

        backButton.tap()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 3))
    }

    @MainActor
    func testProductionRootNavigationRestoresTabBarWithBackSwipe() {
        let app = launchProductionUploader()
        XCTAssertTrue(app.navigationBars.firstMatch.buttons.firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.tabBars.firstMatch.exists)

        app.swipeRight()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 3))
    }

    @MainActor
    func testRootTabShellKeepsTabBarHiddenAcrossNestedPushes() {
        let app = launchDynamicDetailFixture(
            usesRootTabShell: true
        )
        let forwardContent = app.staticTexts["转发动态测试内容"]
        scrollToElement(forwardContent, in: app)
        forwardContent.tap()

        let originalTapArea = app.buttons[
            "dynamic.feed.originalDetailTapArea.323456789.423456789"
        ]
        scrollToElement(originalTapArea, in: app)
        originalTapArea.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()

        XCTAssertTrue(app.scrollViews["dynamic.detail.scroll"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.tabBars.firstMatch.exists)

        app.navigationBars.firstMatch.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["转发动态测试内容"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.tabBars.firstMatch.exists)

        app.navigationBars.firstMatch.buttons.firstMatch.tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 3))
    }

    @MainActor
    func testRootNavigationShowsNativeSearchAndPreservesState() {
        let app = launchDynamicDetailFixture(
            usesRootTabShell: true
        )
        XCTAssertTrue(app.tabBars.buttons["搜索"].waitForExistence(timeout: 5))
        app.tabBars.buttons["搜索"].tap()

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(
            searchField.waitForExistence(timeout: 3),
            "搜索框应挂载在搜索根 NavigationStack"
        )
        XCTAssertTrue(
            app.navigationBars.firstMatch.staticTexts["搜索"].waitForExistence(timeout: 3),
            "搜索页应保留系统导航标题"
        )
        searchField.tap()
        searchField.typeText("导航实验")

        app.buttons["fixture.search.openDetail"].tap()
        XCTAssertTrue(app.scrollViews["dynamic.detail.scroll"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.tabBars.firstMatch.exists)

        app.navigationBars.firstMatch.buttons.firstMatch.tap()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))
        XCTAssertEqual(searchField.value as? String, "导航实验")
        XCTAssertEqual(
            app.staticTexts["fixture.search.queryValue"].label,
            "导航实验"
        )

        for tab in ["首页", "动态", "直播", "我的"] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(
                searchField.waitForNonExistence(timeout: 3),
                "切换到\(tab)后不应残留搜索栏"
            )
            XCTAssertTrue(
                app.navigationBars.firstMatch.staticTexts[tab].waitForExistence(timeout: 3),
                "切换到\(tab)后应恢复对应导航标题"
            )

            app.tabBars.buttons["搜索"].tap()
            XCTAssertTrue(searchField.waitForExistence(timeout: 3))
            XCTAssertEqual(searchField.value as? String, "导航实验")
        }
    }

    @MainActor
    func testRootTabShellSwipeFromOriginalReturnsToForwardDetail() {
        let app = launchDynamicDetailFixture(
            usesRootTabShell: true
        )
        let forwardContent = app.staticTexts["转发动态测试内容"]
        scrollToElement(forwardContent, in: app)
        forwardContent.tap()

        let originalTapArea = app.buttons[
            "dynamic.feed.originalDetailTapArea.323456789.423456789"
        ]
        scrollToElement(originalTapArea, in: app)
        originalTapArea.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()

        XCTAssertFalse(app.staticTexts["转发动态测试内容"].exists)
        XCTAssertTrue(app.navigationBars.firstMatch.buttons.firstMatch.exists)

        app.swipeRight()

        XCTAssertTrue(app.scrollViews["dynamic.detail.scroll"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["转发动态测试内容"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testRootTabShellPreservesDynamicRootAcrossTabSwitches() {
        let app = launchDynamicDetailFixture(
            enablesAnimations: true,
            usesRootTabShell: true
        )

        let content = app.staticTexts["图文动态测试内容"]
        XCTAssertTrue(content.waitForExistence(timeout: 5))

        app.tabBars.buttons["我的"].tap()
        XCTAssertFalse(content.exists)

        app.tabBars.buttons["动态"].tap()
        XCTAssertTrue(content.waitForExistence(timeout: 3))
    }

    @MainActor
    private func launchProductionUploader() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-cc.bili.display.minimizesTabBarOnScroll.v1", "YES",
            "--start-uploader-mid", "2",
        ]
        app.launch()
        return app
    }

    @MainActor
    private func launchDynamicDetailFixture(
        enablesAnimations: Bool = false,
        usesRootTabShell: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-fixture", "dynamicDetail",
            "--ui-test-reset-state",
        ]
        if enablesAnimations {
            app.launchArguments.append("--ui-test-enable-animations")
        }
        if usesRootTabShell {
            app.launchArguments.append("--ui-test-root-tab-shell")
        }
        app.launch()
        return app
    }

    @MainActor
    private func scrollToElement(_ element: XCUIElement, in app: XCUIApplication) {
        let scrollView = app.scrollViews.firstMatch
        for _ in 0..<8 {
            if element.exists, element.isHittable {
                return
            }
            scrollView.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }

    @MainActor
    private func waitForHittableState(
        _ isHittable: Bool,
        element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while element.isHittable != isHittable, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return element.isHittable == isHittable
    }

    @MainActor
    private func waitForFrameAbove(
        _ initialFrame: CGRect,
        element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while element.exists,
              element.frame.minY >= initialFrame.minY - 20,
              Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return !element.exists || element.frame.minY < initialFrame.minY - 20
    }
}
