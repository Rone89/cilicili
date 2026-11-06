import XCTest

/// 分P/分集/合集选择器回归：紧凑选择为默认行为，单P/单集隐藏。
final class VideoDetailPageSelectorUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 简介区的 shell 容器会把 `video.detail.summary` 标识符传播到所有子元素，
    /// 分P行改用稳定的前缀标签查询（`accessibilityLabel` 以「分P，当前」开头）。
    @MainActor
    private func compactPageRow(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "分P，当前")).firstMatch
    }

    /// 分集（番剧）紧凑行同样以「分集，当前」前缀标签查询。
    @MainActor
    private func episodeCompactRow(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "分集，当前")).firstMatch
    }

    /// 合集紧凑行以「合集，当前」前缀标签查询（与分P/分集同样的标识符传播规避策略）。
    @MainActor
    private func seasonCompactRow(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "合集，当前")).firstMatch
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-reset-state", "--start-tab", "home",
            "--ui-test-video-detail-network", "--ui-test-player-controls-persistent",
            "--ui-test-video-multi-page",
            "--start-bvid", "BV1xx411c7mD",
        ]
        app.launch()
        return app
    }

    @MainActor
    private func launchAppWithSeason() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-reset-state", "--start-tab", "home",
            "--ui-test-video-detail-network", "--ui-test-player-controls-persistent",
            "--ui-test-video-season",
            "--start-bvid", "BV1xx411c7mD",
        ]
        app.launch()
        return app
    }

    /// 紧凑选择已是默认行为：不再需要实验开关参数。
    @MainActor
    func testCompactPageSelectorShowsCurrentPartAndOpensSheet() throws {
        let app = launchApp()
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

        let closeButton = app.buttons["video.detail.pageSheet.close"].firstMatch
        XCTAssertTrue(closeButton.exists, app.debugDescription)
        let orderButton = app.buttons["video.detail.pageSheet.order"].firstMatch
        XCTAssertTrue(orderButton.exists, app.debugDescription)

        // 倒序：第一行应变为 P3。
        let thirdPage = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "P3 第三分 P"))
            .firstMatch
        let secondPage = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "P2 第二分 P"))
            .firstMatch
        XCTAssertTrue(secondPage.waitForExistence(timeout: 10), app.debugDescription)
        orderButton.tap()
        XCTAssertTrue(thirdPage.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertLessThan(thirdPage.frame.minY, secondPage.frame.minY, "倒序时 P3 应在 P2 上方")
        orderButton.tap()
        XCTAssertLessThan(secondPage.frame.minY, thirdPage.frame.minY, "恢复正序后 P2 应在 P3 上方")

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
    func testCompactEpisodeSelectorForPgcUsesSharedSheet() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-reset-state", "--start-tab", "home",
            "--ui-test-video-detail-network", "--ui-test-player-controls-persistent",
            "--start-bvid", "ep3001",
        ]
        app.launch()

        let compact = episodeCompactRow(in: app)
        XCTAssertTrue(compact.waitForExistence(timeout: 25), app.debugDescription)
        XCTAssertTrue(compact.label.contains("3 集"), compact.label)
        // 经典横滑分集瓦片已随紧凑选择转正移除。
        XCTAssertFalse(
            app.buttons["展开全部分集"].firstMatch.exists,
            app.debugDescription
        )

        compact.tap()

        let sheet = app.descendants(matching: .any)["video.detail.pageSheet"].firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), app.debugDescription)

        let secondEpisode = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "第2话"))
            .firstMatch
        XCTAssertTrue(secondEpisode.waitForExistence(timeout: 10), app.debugDescription)
        secondEpisode.tap()

        let updatedLabel = NSPredicate(format: "label CONTAINS %@", "第2话")
        expectation(for: updatedLabel, evaluatedWith: compact, handler: nil)
        waitForExpectations(timeout: 10, handler: nil)

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

    /// 合集紧凑选择同样是默认行为：无实验参数时直接出现。
    @MainActor
    func testCompactSeasonSelectorForUgcUsesSharedSheet() throws {
        let app = launchAppWithSeason()

        let compact = seasonCompactRow(in: app)
        XCTAssertTrue(compact.waitForExistence(timeout: 25), app.debugDescription)
        XCTAssertTrue(compact.label.contains("合集视频 1"), compact.label)
        XCTAssertTrue(compact.label.contains("3 个"), compact.label)
        XCTAssertFalse(
            app.buttons["展开全部合集"].firstMatch.exists,
            "紧凑形态下不应再显示经典横滑菜单的展开按钮"
        )

        compact.tap()

        let sheet = app.descendants(matching: .any)["video.detail.pageSheet"].firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(
            app.buttons["video.detail.pageSheet.close"].firstMatch.exists,
            app.debugDescription
        )

        let secondEpisode = app.buttons
            .matching(NSPredicate(format: "label == %@", "合集视频 2"))
            .firstMatch
        XCTAssertTrue(secondEpisode.waitForExistence(timeout: 10), app.debugDescription)
        secondEpisode.tap()

        let updatedLabel = NSPredicate(format: "label CONTAINS %@", "合集视频 2")
        expectation(for: updatedLabel, evaluatedWith: compact, handler: nil)
        waitForExpectations(timeout: 15, handler: nil)

        let sheetDismissed = NSPredicate(format: "exists == NO")
        expectation(for: sheetDismissed, evaluatedWith: sheet, handler: nil)
        waitForExpectations(timeout: 10, handler: nil)
    }
}
