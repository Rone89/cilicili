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
        let add = openUpdatedDetailMenu("添加到稍后再看", menu: menu, app: app)
        add.tap()
        _ = openUpdatedDetailMenu("从稍后再看移除", menu: menu, app: app)
        app.buttons["复制链接"].tap()
        XCTAssertTrue(waitForAccessibilityValue("已复制链接", on: menu), app.debugDescription)
        app.buttons["video.detail.toolbar-comment"].tap()
        XCTAssertEqual(app.staticTexts["library.fixture.openedVideo"].label, "发表评论")
    }

    private func openUpdatedDetailMenu(_ title: String, menu: XCUIElement, app: XCUIApplication) -> XCUIElement {
        let action = app.buttons[title]
        for _ in 0..<3 {
            menu.tap()
            if action.waitForExistence(timeout: 2) && action.isEnabled { return action }
            // A native Menu snapshots the async loading state at presentation.
            // Dismiss before reopening once the mutation/reload has completed.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.4)).tap()
        }
        XCTFail("Updated watch-later action did not become available: \(title)")
        return action
    }

    private func waitForAccessibilityValue(_ value: String, on element: XCUIElement) -> Bool {
        let updated = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", value),
            object: element
        )
        return XCTWaiter.wait(for: [updated], timeout: 5) == .completed
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

    func testFormerlyDisabledExperimentNowHasProductionActions() {
        let app = launch(["--library-detail-menu", "--library-formerly-disabled"])
        let menu = app.buttons["video.detail.more"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["video.detail.share"].exists)
        XCTAssertFalse(app.buttons["video.detail.toolbar-comment-more"].exists)
        XCTAssertTrue(app.buttons["video.detail.toolbar-comment"].exists)
        XCTAssertTrue(app.buttons["library.manage.select"].exists)
        menu.tap()
        XCTAssertTrue(app.buttons["从稍后再看移除"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["复制链接"].exists)
        XCTAssertTrue(app.buttons["分享"].exists)
    }

    func testProductionToolbarOpensRealCommentComposer() {
        let app = launch(["--library-detail-menu", "--library-comment-composer"])
        let button = app.buttons["video.detail.toolbar-comment"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        let editor = app.textViews["dynamic.comment.composer.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        editor.typeText("测试草稿")
        XCTAssertEqual(editor.value as? String, "测试草稿")
    }

    func testWatchLaterNativeSelectionAndBatchRemoval() {
        let app = launch()
        let select = app.buttons["library.manage.select"]
        XCTAssertTrue(select.waitForExistence(timeout: 5))
        select.tap()
        selectAll(in: app)
        XCTAssertEqual(app.staticTexts["library.fixture.openedVideo"].label, "未打开视频")
        let remove = app.buttons["library.manage.remove"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        // SwiftUI exports both the confirmation wrapper and its child button.
        let confirm = app.sheets["移除所选的 3 项？"].buttons
            .matching(identifier: "library.manage.confirmRemove").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        XCTAssertTrue(app.alerts["管理结果"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.staticTexts["已完成 3 项"].exists)
        app.alerts.buttons["好"].tap()
        XCTAssertTrue(app.staticTexts["稍后再看里还没有视频"].waitForExistence(timeout: 3))
    }


    func testWatchLaterBatchProgressCountsOnlyCompletedRequests() {
        verifyWatchLaterBatchProgress(failsSecondBatch: false)
    }

    func testWatchLaterBatchProgressStopsAtLastConfirmedBatchOnFailure() {
        verifyWatchLaterBatchProgress(failsSecondBatch: true)
    }

    func testWatchLaterRetryDoesNotRepeatCompletedBatch() {
        verifyWatchLaterBatchProgress(failsSecondBatch: true, retry: true)
    }

    private func verifyWatchLaterBatchProgress(failsSecondBatch: Bool, retry: Bool = false) {
        var arguments = ["--library-batch-progress"]
        if failsSecondBatch { arguments.append("--library-batch-failure") }
        if retry { arguments.append("--library-batch-retry") }
        let app = launch(arguments)
        app.buttons["library.manage.select"].tap()
        selectAll(in: app)
        app.buttons["library.manage.remove"].tap()
        let confirm = app.sheets["移除所选的 25 项？"].buttons
            .matching(identifier: "library.manage.confirmRemove").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        let count = app.staticTexts["library.manage.progress.count"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        XCTAssertEqual(count.label, "已完成 0 / 25 项")
        let firstBatch = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "已完成 20 / 25 项"),
            object: count
        )
        XCTAssertEqual(XCTWaiter.wait(for: [firstBatch], timeout: 10), .completed)
        XCTAssertTrue(app.alerts["管理结果"].waitForExistence(timeout: 10))
        if failsSecondBatch {
            let result = app.alerts.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "已完成 20 项", "测试批次失败")
            ).firstMatch
            XCTAssertTrue(result.exists)
        } else {
            XCTAssertTrue(app.alerts.staticTexts["已完成 25 项"].exists)
        }
        if retry {
            let retryButton = app.alerts.buttons["library.manage.retry"]
            XCTAssertTrue(retryButton.waitForExistence(timeout: 5))
            retryButton.tap()
            XCTAssertTrue(count.waitForExistence(timeout: 5))
            XCTAssertEqual(count.label, "已完成 0 / 5 项")
            XCTAssertTrue(app.alerts["管理结果"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.alerts.staticTexts["已完成 5 项"].exists)
            app.alerts.buttons["好"].tap()
            XCTAssertTrue(app.staticTexts["稍后再看里还没有视频"].waitForExistence(timeout: 5))
            return
        }
        app.alerts.buttons["好"].tap()
        XCTAssertFalse(count.exists)
        if failsSecondBatch {
            XCTAssertTrue(app.staticTexts["测试视频 21"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["测试视频 25"].exists)
            XCTAssertFalse(app.staticTexts["测试视频 1"].exists)
        } else {
            XCTAssertTrue(app.staticTexts["稍后再看里还没有视频"].waitForExistence(timeout: 5))
        }
    }

    func testLoggedOutHasNoManagementActions() {
        let app = launch(["--library-logged-out"])
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
        selectAll(in: app)
        let copy = app.buttons["library.manage.copy"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        copy.tap()
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
        // Compact presentations expose Cancel; popovers use a dismissal region.
        let cancel = app.buttons["取消"]
        if cancel.waitForExistence(timeout: 3) {
            cancel.tap()
        } else {
            let dismiss = app.otherElements["PopoverDismissRegion"]
            XCTAssertTrue(dismiss.waitForExistence(timeout: 3))
            dismiss.tap()
        }
        XCTAssertTrue(app.staticTexts["测试视频 1"].exists)
        XCTAssertTrue(app.staticTexts["测试视频 3"].exists)
    }

    func testWatchLaterSearchLimitsBatchRemovalToMatches() {
        let app = launch()
        let search = app.textFields["library.watchLater.search.field"]
        XCTAssertTrue(search.waitForExistence(timeout: 5), app.debugDescription)
        search.tap()
        search.typeText("BVfixture2\n")
        XCTAssertTrue(app.staticTexts["测试视频 2"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["library.watchLater.search.scope"].exists)
        XCTAssertFalse(app.staticTexts["测试视频 1"].exists)
        XCTAssertFalse(app.staticTexts["测试视频 3"].exists)
        let select = app.buttons["library.manage.select"]
        XCTAssertTrue(select.waitForExistence(timeout: 5))
        select.tap()
        selectAll(in: app)
        app.buttons["library.manage.remove"].tap()
        let confirm = app.sheets["移除所选的 1 项？"].buttons
            .matching(identifier: "library.manage.confirmRemove").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.alerts["管理结果"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.staticTexts["已完成 1 项"].exists)
        app.alerts.buttons["好"].tap()
        XCTAssertTrue(app.staticTexts["测试视频 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["测试视频 3"].exists)
        XCTAssertFalse(app.staticTexts["测试视频 2"].exists)
    }

    func testFavoriteSearchOnlyLoadedItemsAndLoadMore() {
        let app = launch(["--library-favorites", "--library-paginated"])
        app.staticTexts["来源收藏夹"].tap()
        XCTAssertTrue(app.staticTexts["测试视频 1"].waitForExistence(timeout: 5))
        let search = app.textFields["library.favorite.search.field"]
        XCTAssertTrue(search.waitForExistence(timeout: 5), app.debugDescription)
        search.tap()
        search.typeText("BVfixture30\n")
        XCTAssertTrue(app.staticTexts["已加载的收藏中没有匹配结果"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["library.favorite.search.scope"].exists)
        XCTAssertFalse(app.staticTexts["测试视频 30"].exists)
        let more = app.buttons["library.favorite.search.loadMore"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()
        XCTAssertTrue(app.staticTexts["测试视频 30"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["测试视频 1"].exists)
        let select = app.buttons["library.manage.select"]
        XCTAssertTrue(select.waitForExistence(timeout: 5))
        select.tap()
        selectAll(in: app)
        app.buttons["library.manage.remove"].tap()
        let confirm = app.sheets["移除所选的 1 项？"].buttons
            .matching(identifier: "library.manage.confirmRemove").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.alerts["管理结果"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.staticTexts["已完成 1 项"].exists)
        app.alerts.buttons["好"].tap()
        XCTAssertTrue(app.staticTexts["测试视频 1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["测试视频 30"].exists)
    }

    func testFavoriteMoveUpdatesBothLists() {
        let app = launch(["--library-favorites"])
        let folder = app.staticTexts["来源收藏夹"]
        XCTAssertTrue(folder.waitForExistence(timeout: 5))
        folder.tap()
        let select = app.buttons["library.manage.select"]
        XCTAssertTrue(select.waitForExistence(timeout: 5))
        select.tap()
        selectAll(in: app)
        let move = app.buttons["library.manage.move"]
        XCTAssertTrue(move.waitForExistence(timeout: 5))
        move.tap()
        let target = app.staticTexts["目标收藏夹"]
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        target.tap()
        XCTAssertTrue(app.alerts["管理结果"].waitForExistence(timeout: 5))
        app.alerts.buttons["好"].tap()
        XCTAssertTrue(app.staticTexts["这个收藏夹还没有视频"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        let destination = app.staticTexts["目标收藏夹"]
        XCTAssertTrue(destination.waitForExistence(timeout: 5), app.debugDescription)
        destination.tap()
        XCTAssertTrue(app.staticTexts["测试视频 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["测试视频 3"].exists)
    }


    func testFavoriteMoveRetrySkipsConfirmedTargetAddition() {
        let app = launch(["--library-favorites", "--library-move-retry"])
        app.staticTexts["来源收藏夹"].tap()
        let select = app.buttons["library.manage.select"]
        XCTAssertTrue(select.waitForExistence(timeout: 5))
        select.tap()
        selectAll(in: app)
        app.buttons["library.manage.move"].tap()
        app.staticTexts["目标收藏夹"].tap()
        XCTAssertTrue(app.alerts["管理结果"].waitForExistence(timeout: 5))
        let partial = app.alerts.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "3 项已加入目标收藏夹")
        ).firstMatch
        XCTAssertTrue(partial.exists)
        let retry = app.alerts.buttons["library.manage.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        retry.tap()
        let completed = app.alerts.staticTexts["已完成 3 项"]
        XCTAssertTrue(completed.waitForExistence(timeout: 5))
        app.alerts.buttons["好"].tap()
        XCTAssertTrue(app.staticTexts["这个收藏夹还没有视频"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        app.staticTexts["目标收藏夹"].tap()
        XCTAssertTrue(app.staticTexts["测试视频 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["测试视频 3"].exists)
    }


    func testWatchLaterSortingAndSearchKeepRowsManageable() {
        let app = launch(["--library-sorting"])
        let sort = app.buttons["library.watchLater.sort"]
        XCTAssertTrue(sort.waitForExistence(timeout: 5))
        sort.tap()
        app.buttons["时长从长到短"].tap()
        let reordered = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "library.video."))
                    .allElementsBoundByIndex
                return rows.map(\.identifier) == [
                    "library.video.BVfixture3", "library.video.BVfixture2", "library.video.BVfixture1"
                ]
            },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [reordered], timeout: 5), .completed)
        XCTAssertTrue(app.staticTexts["library.watchLater.sort.scope"].exists)
        let search = app.textFields["library.watchLater.search.field"]
        search.tap()
        search.typeText("BVfixture2\n")
        XCTAssertTrue(app.staticTexts["测试视频 2"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["测试视频 1"].exists)
        XCTAssertFalse(app.staticTexts["测试视频 3"].exists)
        app.buttons["library.manage.select"].tap()
        selectAll(in: app)
        XCTAssertTrue(app.buttons["library.manage.remove"].isEnabled)
        // Changing order clears the old selection before another bulk action.
        sort.tap()
        app.buttons["默认顺序"].tap()
        XCTAssertFalse(app.buttons["library.manage.remove"].isEnabled)
    }


    func testWatchLaterViewingFilterScopesSelectionAndRemoval() {
        let app = launch(["--library-watch-status"])
        let menu = app.buttons["library.watchLater.actions"]
        menu.tap()
        app.buttons["可继续观看"].tap()
        XCTAssertTrue(app.staticTexts["测试视频 1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["测试视频 2"].exists)
        XCTAssertFalse(app.staticTexts["测试视频 3"].exists)
        XCTAssertTrue(app.staticTexts["library.watchLater.filter.scope"].exists)
        let search = app.textFields["library.watchLater.search.field"]
        search.tap()
        search.typeText("BVfixture2\n")
        XCTAssertTrue(app.staticTexts["已加载的稍后再看中没有匹配结果"].waitForExistence(timeout: 5))
        app.buttons["清除搜索"].tap()

        menu.tap()
        app.buttons["已看完"].tap()
        XCTAssertTrue(app.staticTexts["测试视频 2"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["测试视频 1"].exists)
        XCTAssertFalse(app.staticTexts["测试视频 3"].exists)
        app.buttons["library.manage.select"].tap()
        selectAll(in: app)
        menu.tap()
        app.buttons["全部"].tap()
        XCTAssertFalse(app.buttons["library.manage.remove"].isEnabled)
        XCTAssertTrue(app.staticTexts["测试视频 3"].exists)

        menu.tap()
        app.buttons["已看完"].tap()
        selectAll(in: app)
        app.buttons["library.manage.remove"].tap()
        let confirm = app.sheets["移除所选的 1 项？"].buttons
            .matching(identifier: "library.manage.confirmRemove").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.alerts["管理结果"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.staticTexts["已完成 1 项"].exists)
        app.alerts.buttons["好"].tap()
        XCTAssertTrue(app.staticTexts["测试视频 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["测试视频 3"].exists)
        XCTAssertFalse(app.staticTexts["测试视频 2"].exists)
    }


    func testCommentSubmissionPreservesTypingAfterSendStarted() {
        let app = launch([
            "--library-detail-menu", "--library-comment-composer", "--library-comment-delayed-submit"
        ])
        app.buttons["video.detail.toolbar-comment"].tap()
        let editor = app.textViews["dynamic.comment.composer.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeText("before")
        app.buttons["dynamic.comment.composer.send"].tap()
        editor.typeText("after")
        let preserved = app.staticTexts["dynamic.comment.composer.newerDraftPreserved"]
        XCTAssertTrue(preserved.waitForExistence(timeout: 15))
        XCTAssertTrue(editor.exists)
        XCTAssertEqual(editor.value as? String, "beforeafter")
        XCTAssertTrue(app.buttons["dynamic.comment.composer.send"].isEnabled)
    }

    private func selectAll(in app: XCUIApplication) {
        let selectAll = app.buttons["library.manage.selectAll"]
        XCTAssertTrue(selectAll.waitForExistence(timeout: 5), app.debugDescription)
        selectAll.tap()
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "libraryManagement"] + extra
        app.launch()
        let ready: XCUIElement
        if extra.contains("--library-logged-out") {
            ready = app.navigationBars.firstMatch
        } else {
            ready = extra.contains("--library-favorites")
                ? app.staticTexts["来源收藏夹"] : app.buttons["library.video.BVfixture1"]
        }
        XCTAssertTrue(ready.waitForExistence(timeout: 15), app.debugDescription)
        return app
    }
}
