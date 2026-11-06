import XCTest

/// 分P选择器回归：经典横滑瓦片形态、紧凑实验形态与单P隐藏。
final class VideoDetailPageSelectorUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testClassicPageSelectorKeepsTileRowWhenExperimentOff() throws {
        let app = launchApp(compactSelectorEnabled: false)

        let expandButton = app.buttons["展开全部分P"].firstMatch
        XCTAssertTrue(expandButton.waitForExistence(timeout: 20), app.debugDescription)

        let firstTile = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "P1 测试分 P"))
            .firstMatch
        XCTAssertTrue(firstTile.exists, app.debugDescription)
        XCTAssertFalse(
            compactPageRow(in: app).exists,
            app.debugDescription
        )
    }

    /// 简介区的 shell 容器会把 `video.detail.summary` 标识符传播到所有子元素，
    /// 分P行改用稳定的前缀标签查询（`accessibilityLabel` 以「分P，当前」开头）。
    @MainActor
    private func compactPageRow(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "分P，当前")).firstMatch
    }

    @MainActor
    func testCompactPageSelectorShowsCurrentPartAndOpensSheet() throws {
        let app = launchApp(compactSelectorEnabled: true)
        let compact = compactPageRow(in: app)
        XCTAssertTrue(compact.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(
            app.buttons["展开全部分P"].firstMatch.exists,
            "紧凑形态下不应再显示经典横滑菜单的展开按钮"
        )
        XCTAssertTrue(compact.label.contains("P1"), compact.label)
        XCTAssertTrue(compact.label.contains("测试分 P"), compact.label)
        XCTAssertTrue(compact.label.contains("3 P"), compact.label)

        compact.tap()

        let sheet = app.descendants(matching: .any)["video.detail.pageSheet"].firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), app.debugDescription)

        // 弹窗瓦片的 label 会被嵌套无障碍元素拼接，用前缀匹配。
        let secondPage = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "P2 第二分 P"))
            .firstMatch
        XCTAssertTrue(secondPage.waitForExistence(timeout: 10), app.debugDescription)
        secondPage.tap()

        let updatedLabel = NSPredicate(format: "label CONTAINS %@", "P2")
        expectation(for: updatedLabel, evaluatedWith: compact, handler: nil)
        waitForExpectations(timeout: 10, handler: nil)
        XCTAssertTrue(compact.label.contains("第二分 P"), compact.label)

        let sheetDismissed = NSPredicate(format: "exists == NO")
        expectation(for: sheetDismissed, evaluatedWith: sheet, handler: nil)
        waitForExpectations(timeout: 10, handler: nil)
    }

    @MainActor
    func testSinglePageVideoHidesPageSelector() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-reset-state", "--start-tab", "home",
            "--ui-test-video-detail-network", "--ui-test-player-controls-persistent",
            "--start-bvid", "BV1xx411c7mD",
        ]
        app.launch()

        let playerFrame = app.descendants(matching: .any)["ui.videoDetail.playerFrame"].firstMatch
        XCTAssertTrue(playerFrame.waitForExistence(timeout: 20), app.debugDescription)

        XCTAssertFalse(
            app.buttons["展开全部分P"].firstMatch.exists,
            app.debugDescription
        )
        XCTAssertFalse(
            compactPageRow(in: app).exists,
            app.debugDescription
        )
    }

    @MainActor
    private func launchApp(compactSelectorEnabled: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments: [String] = [
            "--ui-test-reset-state", "--start-tab", "home",
            "--ui-test-video-detail-network", "--ui-test-player-controls-persistent",
            "--ui-test-video-multi-page",
            "--start-bvid", "BV1xx411c7mD",
        ]
        if compactSelectorEnabled {
            arguments.append(contentsOf: [
                "-cc.bili.videoDetail.compactPageSelectorExperimentEnabled.v1", "YES",
            ])
        }
        app.launchArguments = arguments
        app.launch()
        return app
    }
}
