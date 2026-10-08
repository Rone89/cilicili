import XCTest

@MainActor
final class AccountLibraryManagementUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testWatchLaterNativeSelectionAndBatchRemoval() {
        let app = launch()
        let select = app.buttons["library.manage.select"]
        XCTAssertTrue(select.waitForExistence(timeout: 5))
        select.tap()
        app.buttons["library.manage.selectAll"].tap()
        XCTAssertEqual(app.staticTexts["library.fixture.openedVideo"].label, "未打开视频")
        app.toolbars.buttons["移除"].tap()
        let matches = app.buttons.matching(identifier: "移除")
        let confirm = matches.element(boundBy: matches.count - 1)
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        XCTAssertTrue(app.alerts["管理结果"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.staticTexts["已完成 3 项"].exists)
        app.alerts.buttons["好"].tap()
        XCTAssertTrue(app.staticTexts["稍后再看里还没有视频"].waitForExistence(timeout: 3))
    }

    func testExperimentOffAndLoggedOutHaveNoManagementActions() {
        let app = launch(["--library-off"])
        XCTAssertTrue(app.staticTexts["测试视频 1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["library.manage.select"].exists)
        app.terminate()
        app.launchArguments = ["--ui-test-fixture", "libraryManagement", "--library-logged-out"]
        app.launch()
        XCTAssertTrue(app.staticTexts["登录后同步稍后再看"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["library.manage.select"].exists)
    }

    func testFavoriteCopyRetainsSourceRows() {
        let app = launch(["--library-favorites"])
        let folder = app.staticTexts["来源收藏夹"]
        XCTAssertTrue(folder.waitForExistence(timeout: 5))
        folder.tap()
        let select = app.buttons["library.manage.select"]
        XCTAssertTrue(select.waitForExistence(timeout: 5))
        select.tap()
        app.buttons["library.manage.selectAll"].tap()
        app.toolbars.buttons["复制"].tap()
        let target = app.staticTexts["目标收藏夹"]
        XCTAssertTrue(target.waitForExistence(timeout: 3))
        target.tap()
        XCTAssertTrue(app.alerts["管理结果"].waitForExistence(timeout: 5))
        app.alerts.buttons["好"].tap()
        XCTAssertTrue(app.staticTexts["测试视频 1"].exists)
        XCTAssertTrue(app.staticTexts["测试视频 3"].exists)
    }

    func testOrdinaryTapAndCancelClearKeepVideos() {
        let app = launch()
        let video = app.buttons["library.video.BVfixture1"]
        XCTAssertTrue(video.waitForExistence(timeout: 5))
        video.tap()
        XCTAssertEqual(app.staticTexts["library.fixture.openedVideo"].label, "测试视频 1")
        app.buttons["library.watchLater.actions"].tap()
        app.buttons["清空稍后再看"].tap()
        XCTAssertTrue(app.buttons["清空全部"].waitForExistence(timeout: 3))
        // iOS 27 presents this confirmation as a popover; cancellation uses its dismissal region.
        let dismiss = app.otherElements["PopoverDismissRegion"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 3))
        dismiss.tap()
        XCTAssertTrue(app.staticTexts["测试视频 1"].exists)
        XCTAssertTrue(app.staticTexts["测试视频 3"].exists)
    }

    func testFavoriteMoveUpdatesBothLists() {
        let app = launch(["--library-favorites"])
        let folder = app.staticTexts["来源收藏夹"]
        XCTAssertTrue(folder.waitForExistence(timeout: 5))
        folder.tap()
        let select = app.buttons["library.manage.select"]
        XCTAssertTrue(select.waitForExistence(timeout: 5))
        select.tap()
        app.buttons["library.manage.selectAll"].tap()
        app.toolbars.buttons["移动"].tap()
        app.staticTexts["目标收藏夹"].tap()
        XCTAssertTrue(app.alerts["管理结果"].waitForExistence(timeout: 5))
        app.alerts.buttons["好"].tap()
        XCTAssertTrue(app.staticTexts["这个收藏夹还没有视频"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        app.staticTexts["目标收藏夹"].tap()
        XCTAssertTrue(app.staticTexts["测试视频 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["测试视频 3"].exists)
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "libraryManagement"] + extra
        app.launch()
        return app
    }
}
