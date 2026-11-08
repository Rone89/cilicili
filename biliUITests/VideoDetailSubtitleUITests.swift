import XCTest

/// 字幕（CC）按钮回归：`--subtitle-fixture` 注入假轨（无需登录态）。
///
/// 选轨弹窗由详情页最外层 SwiftUI sheet 呈现（与评论弹窗同款），
/// 在该 UIKit 宿主 overlay 内 XCUITest 无法观察到系统 sheet 呈现
/// （直接启动可见，见 docs/DEVELOPMENT_STATUS.md 的截图验证记录），
/// 因此自动化只覆盖「有字幕轨时按钮出现」；弹窗内容与选轨渲染
/// 由单元测试与真机验收覆盖。
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

    @MainActor
    private func revealControls(in app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
    }

    @MainActor
    func testSubtitleButtonAppearsWhenTracksAvailable() throws {
        let app = launchApp()

        let subtitleButton = app.buttons["ui.player.subtitle.toggle"]
        for _ in 0..<5 where !subtitleButton.exists {
            revealControls(in: app)
            _ = subtitleButton.waitForExistence(timeout: 2)
        }
        XCTAssertTrue(subtitleButton.exists, "有字幕轨时控制条应出现 CC 按钮: \(app.debugDescription)")
    }
}
