import XCTest

@MainActor
final class AccountLibraryManagementUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testFavoriteFolderToolbarIsUniqueAndPrivacyUsesText() {
        let app = launch(["--library-favorites"])
        XCTAssertTrue(app.staticTexts["来源收藏夹"].waitForExistence(timeout: 5))
        let menus = app.buttons.matching(identifier: "library.favorites.actions")
        XCTAssertEqual(menus.count, 1)
        XCTAssertTrue(app.staticTexts["公开"].firstMatch.exists)
        XCTAssertFalse(app.images["globe"].exists)
        XCTAssertFalse(app.images["lock"].exists)
        menus.firstMatch.tap()
        app.buttons["创建收藏夹"].tap()
        XCTAssertTrue(app.textFields["名称"].waitForExistence(timeout: 5))
        app.buttons["取消"].tap()
        XCTAssertEqual(menus.count, 1)
    }

    func testDetailMoreMenuWatchLaterRoundTrip() {
        let app = launch(["--library-detail-menu"])
        let menu = app.buttons["video.detail.more"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        let remove = app.buttons["从稍后再看移除"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["复制链接"].exists)
        XCTAssertTrue(app.buttons["分享"].exists)
        XCTAssertFalse(app.buttons["刷新评论区"].exists)
        remove.tap()
        menu.tap()
        let add = app.buttons["添加到稍后再看"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        menu.tap()
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        app.buttons["复制链接"].tap()
        XCTAssertEqual(menu.value as? String, "已复制链接")
        app.buttons["video.detail.toolbar-comment"].tap()
        XCTAssertEqual(app.staticTexts["library.fixture.openedVideo"].label, "发表评论")
    }

    func testDetailMoreMenuPresentsSystemShareSheet() {
        let app = launch(["--library-detail-menu"])
        let menu = app.buttons["video.detail.more"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        app.buttons["分享"].tap()
        let shareSheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(shareSheet.waitForExistence(timeout: 5))
    }

    func testDetailMoreMenuExperimentOffPreservesCommentActions() {
        let app = launch(["--library-detail-menu", "--library-off"])
        XCTAssertTrue(app.buttons["video.detail.share"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["video.detail.more"].exists)
        XCTAssertFalse(app.buttons["video.detail.toolbar-comment"].exists)
        let menu = app.buttons["video.detail.toolbar-comment-more"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        XCTAssertTrue(app.buttons["评论"].exists)
        XCTAssertTrue(app.buttons["刷新评论区"].exists)
        XCTAssertFalse(app.buttons["video.detail.watchLater"].exists)
        app.buttons["刷新评论区"].tap()
        XCTAssertEqual(app.staticTexts["library.fixture.openedVideo"].label, "刷新评论区")
    }

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
