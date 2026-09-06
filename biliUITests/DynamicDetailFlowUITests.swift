import XCTest

final class DynamicDetailFlowUITests: XCTestCase {
    @MainActor
    func testTelegramInputStyleInteractionBarGeometry() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-fixture", "dynamicDetail",
            "--ui-test-reset-state",
            "--ui-test-root-tab-shell",
            "--ui-test-telegram-input-style"
        ]
        app.launch()
        let content = app.staticTexts["图文动态测试内容"]
        XCTAssertTrue(content.waitForExistence(timeout: 5))
        content.tap()

        let like = app.buttons["dynamic.detail.composer.like"]
        let comment = app.buttons["dynamic.detail.composer.comment"]
        let favorite = app.buttons["dynamic.detail.composer.favorite"]
        XCTAssertTrue(like.waitForExistence(timeout: 5))
        XCTAssertTrue(comment.exists)
        XCTAssertTrue(favorite.exists)

        let window = app.windows.firstMatch.frame
        XCTAssertEqual(like.frame.width, 44, accuracy: 1)
        XCTAssertEqual(favorite.frame.width, 44, accuracy: 1)
        XCTAssertEqual(comment.frame.height, 40, accuracy: 1)
        XCTAssertEqual(like.frame.minX - window.minX, 24, accuracy: 1)
        XCTAssertEqual(window.maxX - favorite.frame.maxX, 24, accuracy: 1)
        XCTAssertEqual(window.maxY - like.frame.maxY, 28, accuracy: 1)
        XCTAssertEqual(like.frame.minY, favorite.frame.minY, accuracy: 1)
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
