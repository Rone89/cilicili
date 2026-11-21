import XCTest

@MainActor
final class AdaptiveLayoutUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAdaptiveVideoDetailSplitAndFullscreenAcrossOrientations() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-reset-state",
            "--start-tab", "home",
            "--ui-test-video-detail-network",
            "--ui-test-player-controls-persistent",
            "--start-bvid", "BV1xx411c7mD",
        ]
        app.launch()
        addTeardownBlock {
            XCUIDevice.shared.orientation = .portrait
            _ = self.waitForCondition(timeout: 2) {
                app.windows.firstMatch.frame.height >= app.windows.firstMatch.frame.width
            }
            app.terminate()
        }

        let toolbar = element("video.detail.toolbar-picker", in: app).firstMatch
        XCTAssertTrue(toolbar.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.staticTexts["相关推荐"].waitForExistence(timeout: 10), app.debugDescription)

        let playerFrameElement = element("ui.videoDetail.playerFrame", in: app).firstMatch
        XCTAssertTrue(playerFrameElement.waitForExistence(timeout: 10), app.debugDescription)
        let portraitWindowWidth = app.windows.firstMatch.frame.width
        let portraitPlayerFrame = playerFrameElement.frame

        attachScreenshot(app.screenshot(), name: "adaptive-video-detail-portrait")

        let isLargeScreenPortrait = portraitWindowWidth >= 700
        if isLargeScreenPortrait {
            XCTAssertLessThan(
                portraitPlayerFrame.width,
                portraitWindowWidth * 0.72,
                "Large screen portrait (>=700pt) should use two-column split layout, got playerFrame=\(portraitPlayerFrame) windowWidth=\(portraitWindowWidth)"
            )
        } else {
            XCTAssertEqual(
                portraitPlayerFrame.width,
                portraitWindowWidth,
                accuracy: 2,
                "Compact screen portrait should keep full-width stacked player"
            )
        }

        // Rotate to landscape
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscapeWindow = app.windows.firstMatch
        XCTAssertTrue(waitForCondition(timeout: 5) {
            landscapeWindow.frame.width > landscapeWindow.frame.height
        }, "Window did not rotate to landscape: \(landscapeWindow.frame)")

        if isLargeScreenPortrait {
            // Large screen landscape must remain in two-column split (not auto-fullscreen)
            XCTAssertTrue(toolbar.waitForExistence(timeout: 5), "Toolbar should remain visible in iPad landscape split mode")
            let landscapeSplitPlayerFrame = playerFrameElement.frame
            XCTAssertLessThan(
                landscapeSplitPlayerFrame.width,
                landscapeWindow.frame.width * 0.75,
                "iPad landscape must remain in two-column split until fullscreen is tapped, got \(landscapeSplitPlayerFrame)"
            )

            // Switch to comments tab and verify it renders in the right column
            toolbar.buttons["评论"].tap()
            let commentsList = app.tables["comments.list"].firstMatch
            XCTAssertTrue(commentsList.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertGreaterThanOrEqual(
                commentsList.frame.minX,
                landscapeSplitPlayerFrame.maxX - 10,
                "Comments column must sit to the right of the player column"
            )
            attachScreenshot(app.screenshot(), name: "adaptive-video-detail-landscape-split")

            // Tap fullscreen -> enters in-place fullscreen
            let fullscreenButton = fullscreenControl(in: app)
            if !fullscreenButton.exists {
                let surface = app.buttons["ui.player.surface"].firstMatch
                if surface.exists { surface.tap() }
            }
            XCTAssertTrue(fullscreenButton.waitForExistence(timeout: 5), app.debugDescription)
            fullscreenButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

            XCTAssertTrue(waitForCondition(timeout: 5) {
                playerFrameElement.frame.width >= landscapeWindow.frame.width - 4
            }, "Tapping fullscreen on iPad must expand player to full window width, got \(playerFrameElement.frame)")
            attachScreenshot(app.screenshot(), name: "adaptive-video-detail-ipad-fullscreen")

            // Exit fullscreen -> returns to two-column split
            let exitButton = fullscreenControl(in: app)
            if !exitButton.exists {
                let surface = app.buttons["ui.player.surface"].firstMatch
                if surface.exists { surface.tap() }
            }
            XCTAssertTrue(exitButton.waitForExistence(timeout: 5), app.debugDescription)
            exitButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

            XCTAssertTrue(waitForCondition(timeout: 5) {
                playerFrameElement.frame.width < landscapeWindow.frame.width * 0.75
            }, "Exiting fullscreen on iPad must return to two-column split, got \(playerFrameElement.frame)")
            XCTAssertTrue(commentsList.waitForExistence(timeout: 5))
        } else {
            attachScreenshot(app.screenshot(), name: "adaptive-video-detail-iphone-landscape")
        }
    }

    func testAdaptiveRootTabsAndDeveloperToggle() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-reset-state",
            "--start-tab", "home",
        ]
        app.launch()
        addTeardownBlock {
            XCUIDevice.shared.orientation = .portrait
            _ = self.waitForCondition(timeout: 2) {
                app.windows.firstMatch.frame.height >= app.windows.firstMatch.frame.width
            }
            app.terminate()
        }

        let modeMenu = app.buttons["home.feed.modeMenu"].firstMatch
        XCTAssertTrue(modeMenu.waitForExistence(timeout: 15), app.debugDescription)
        attachScreenshot(app.screenshot(), name: "adaptive-root-home-portrait")

        if app.windows.firstMatch.frame.width >= 700 {
            XCUIDevice.shared.orientation = .landscapeLeft
            XCTAssertTrue(waitForCondition(timeout: 5) {
                app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height
            }, "iPad root view must support landscape rotation")
            attachScreenshot(app.screenshot(), name: "adaptive-root-home-landscape")
        }

        // Navigate across tabs on iPad / iPhone and verify adaptive pages render cleanly
        tapRootTab(named: "动态", in: app)
        attachScreenshot(app.screenshot(), name: "adaptive-root-dynamic")

        tapRootTab(named: "搜索", in: app)
        attachScreenshot(app.screenshot(), name: "adaptive-root-search")

        tapRootTab(named: "我的", in: app)
        XCTAssertTrue(
            app.staticTexts["设置"].waitForExistence(timeout: 5)
                || app.buttons["mine.settings.interface"].waitForExistence(timeout: 5),
            app.debugDescription
        )
        attachScreenshot(app.screenshot(), name: "adaptive-root-mine")
    }

    private func tapRootTab(named title: String, in app: XCUIApplication) {
        let tabBarButton = app.tabBars.buttons[title].firstMatch
        if tabBarButton.exists && tabBarButton.isHittable {
            tabBarButton.tap()
            return
        }
        let button = app.buttons[title].firstMatch
        if button.waitForExistence(timeout: 3) && button.isHittable {
            button.tap()
            return
        }
        let staticText = app.staticTexts[title].firstMatch
        if staticText.waitForExistence(timeout: 3) {
            staticText.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: identifier)
    }

    private func fullscreenControl(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(
            format: "identifier == %@ OR label IN %@",
            "ui.player.fullscreen.toggle", ["全屏", "退出全屏"]
        )).firstMatch
    }

    private func attachScreenshot(_ screenshot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitForCondition(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }
}
