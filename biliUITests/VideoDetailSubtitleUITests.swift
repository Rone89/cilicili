import XCTest

/// 字幕（CC）按钮与选轨浮层回归：`--subtitle-fixture` 注入假轨验证完整 UI 链路（无需登录态）。
/// 走真实网络——`--ui-test-video-detail-network` 夹具模式下媒体无法起播、chrome 不挂载。
/// `--subtitle-fixture` 同时让控制条常显（DEBUG 豁免自动隐藏），避免 3 秒窗口竞态。
final class VideoDetailSubtitleUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-reset-state", "--start-tab", "home",
            "--start-bvid", "BV1xx411c7mD",
            "--subtitle-fixture",
        ]
        app.launch()
        return app
    }

    /// 轻点播放器区域呼出控制条。
    @MainActor
    private func revealControls(in app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
    }

    /// 呼出控制条并点击 CC 按钮。`--subtitle-fixture` 已豁免自动隐藏，
    /// 所以呼出后控制条保持常显，点击不再有 3 秒窗口竞态。
    @MainActor
    private func tapSubtitleButton(in app: XCUIApplication) -> Bool {
        let subtitleButton = app.buttons["ui.player.subtitle.toggle"]
        for _ in 0..<4 {
            if subtitleButton.waitForExistence(timeout: 4) {
                subtitleButton.tap()
                return app.buttons["ui.player.subtitle.track.off"].waitForExistence(timeout: 6)
            }
            revealControls(in: app)
        }
        return false
    }

    @MainActor
    func testSubtitleButtonOpensPanelAndSelectsAITrack() throws {
        let app = launchApp()

        XCTAssertTrue(tapSubtitleButton(in: app), "CC 按钮应弹出选轨面板: \(app.debugDescription)")
        XCTAssertTrue(app.buttons["ui.player.subtitle.track.zh"].exists, "真人轨行应显示")
        let aiRow = app.buttons["ui.player.subtitle.track.ai-zh"]
        XCTAssertTrue(aiRow.exists, "AI 轨行应显示")

        aiRow.tap()

        // 浮层选择后关闭，选轨生效：AI 夹具句（0-600s）随播放渲染。
        let cueText = app.staticTexts["AI 夹具句"]
        XCTAssertTrue(cueText.waitForExistence(timeout: 10), "选轨后底部字幕层应渲染当前 cue: \(app.debugDescription)")
    }

    @MainActor
    func testSubtitleHumanTrackRendersCueAndOffersClose() throws {
        let app = launchApp()

        XCTAssertTrue(tapSubtitleButton(in: app), "CC 按钮应弹出选轨面板: \(app.debugDescription)")
        let humanRow = app.buttons["ui.player.subtitle.track.zh"]
        XCTAssertTrue(humanRow.exists, "真人轨行应显示")
        XCTAssertTrue(app.buttons["ui.player.subtitle.track.off"].exists, "面板应提供关闭行")

        humanRow.tap()

        let cueText = app.staticTexts["字幕夹具第一句"]
        XCTAssertTrue(cueText.waitForExistence(timeout: 10), "选真人轨后字幕层应渲染当前 cue: \(app.debugDescription)")
    }
}
