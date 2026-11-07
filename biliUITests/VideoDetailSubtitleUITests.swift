import XCTest

/// 字幕（CC）按钮与选轨弹窗回归：`--subtitle-fixture` 注入假轨验证完整 UI 链路（无需登录态）。
/// 走真实网络——`--ui-test-video-detail-network` 夹具模式下媒体无法起播、chrome 不挂载。
/// `--subtitle-fixture` 同时让控制条常显（DEBUG 豁免自动隐藏），避免 3 秒窗口竞态。
/// 选轨弹窗是 UIKit 系统 action sheet（该宿主结构下 SwiftUI sheet 不会弹出）。
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

    /// 呼出控制条并点击 CC 按钮，直到系统 action sheet 出现。
    @MainActor
    private func openSubtitleSheet(in app: XCUIApplication) -> Bool {
        let subtitleButton = app.buttons["ui.player.subtitle.toggle"]
        for _ in 0..<4 {
            if subtitleButton.waitForExistence(timeout: 4) {
                subtitleButton.tap()
                if app.sheets.firstMatch.waitForExistence(timeout: 6) {
                    return true
                }
            }
            revealControls(in: app)
        }
        return false
    }

    @MainActor
    func testSubtitleButtonOpensSheetAndSelectsAITrack() throws {
        let app = launchApp()

        XCTAssertTrue(openSubtitleSheet(in: app), "CC 按钮应弹出系统选轨弹窗: \(app.debugDescription)")

        let sheet = app.sheets.firstMatch
        // 夹具注入「中文」与「中文（AI）」两条轨 + 关闭/取消行。
        let trackRows = sheet.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "中文"))
        XCTAssertEqual(trackRows.count, 2, "应同时有真人轨与 AI 轨: \(sheet.debugDescription)")
        XCTAssertTrue(sheet.buttons["关闭字幕"].exists, "关闭行应显示")

        // 第二个「中文…」行是 AI 轨（真人轨在前），不依赖括号全/半角形态。
        trackRows.element(boundBy: 1).tap()

        // 弹窗选择后关闭，选轨生效：AI 夹具句（0-600s）随播放渲染。
        let cueText = app.staticTexts["AI 夹具句"]
        XCTAssertTrue(cueText.waitForExistence(timeout: 10), "选轨后底部字幕层应渲染当前 cue: \(app.debugDescription)")
    }

    @MainActor
    func testSubtitleHumanTrackRendersCue() throws {
        let app = launchApp()

        XCTAssertTrue(openSubtitleSheet(in: app), "CC 按钮应弹出系统选轨弹窗: \(app.debugDescription)")
        let humanRow = app.sheets.firstMatch.buttons["中文"]
        XCTAssertTrue(humanRow.exists, "真人轨行应显示")
        humanRow.tap()

        let cueText = app.staticTexts["字幕夹具第一句"]
        XCTAssertTrue(cueText.waitForExistence(timeout: 10), "选真人轨后字幕层应渲染当前 cue: \(app.debugDescription)")
    }
}
