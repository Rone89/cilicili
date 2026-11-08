import XCTest

final class VideoDetailFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func openCommentsTab(in app: XCUIApplication) -> XCUIElement {
        let list = app.tables["comments.list"].firstMatch
        let toolbar = element("video.detail.toolbar-picker", in: app).firstMatch
        XCTAssertTrue(toolbar.waitForExistence(timeout: 15))
        // 点按可能被播放器转场浮层吞掉：确认列表出现，未出现则重按一次。
        toolbar.buttons["评论"].tap()
        if !list.waitForExistence(timeout: 4) {
            toolbar.buttons["评论"].tap()
        }
        XCTAssertTrue(list.waitForExistence(timeout: 10), app.debugDescription)
        return list
    }

    @MainActor
    func testCommentsUIKitListRendersAndScrollsRows() {
        let app = launchVideoDetail(waitForDetailMarker: false)
        let toolbar = element("video.detail.toolbar-picker", in: app).firstMatch
        XCTAssertTrue(toolbar.waitForExistence(timeout: 15))
        toolbar.buttons["评论"].tap()

        let list = openCommentsTab(in: app)
        // 首屏可见行渲染断言（离屏复用 cell 的 hosting 内容 frame 为 0，会被
        // XCUITest 查询剪掉，因此只断言可见元素；整体视觉以截图为准）。
        XCTAssertTrue(
            list.buttons["详情评论 1"].firstMatch.waitForExistence(timeout: 10),
            app.debugDescription
        )

        // 夹具第 4 行是 470pt 的长评论：两屏滑动到第 5 行附近。
        list.swipeUp()
        list.swipeUp()
        XCTAssertTrue(
            list.buttons["详情评论 5"].firstMatch.waitForExistence(timeout: 10),
            app.debugDescription
        )

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Comments UIKit list"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testCommentsUIKitListLoadsNextPageOnScroll() {
        let app = launchVideoDetail(
            waitForDetailMarker: false,
            extraArguments: ["--ui-test-comment-pagination"]
        )
        let toolbar = element("video.detail.toolbar-picker", in: app).firstMatch
        XCTAssertTrue(toolbar.waitForExistence(timeout: 15))
        toolbar.buttons["评论"].tap()

        let list = openCommentsTab(in: app)
        XCTAssertTrue(
            list.buttons["详情评论 1"].firstMatch.waitForExistence(timeout: 10),
            app.debugDescription
        )

        // 持续下滑应自动续载；只有 60 条全部加载完才会出现“没有更多评论了”。
        let endLabel = list.staticTexts["没有更多评论了"].firstMatch
        var reachedEnd = endLabel.exists
        for _ in 0..<30 where !reachedEnd {
            list.swipeUp()
            reachedEnd = endLabel.exists
        }
        XCTAssertTrue(
            reachedEnd || endLabel.waitForExistence(timeout: 10),
            app.debugDescription
        )

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Comments UIKit list paginated"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testCommentsUIKitListTouchStopsDeceleration() {
        let app = launchVideoDetail(
            waitForDetailMarker: false,
            extraArguments: ["--ui-test-comment-pagination"]
        )
        let toolbar = element("video.detail.toolbar-picker", in: app).firstMatch
        XCTAssertTrue(toolbar.waitForExistence(timeout: 15))
        toolbar.buttons["评论"].tap()

        let list = openCommentsTab(in: app)
        XCTAssertTrue(
            element("详情评论 1", in: app).firstMatch.waitForExistence(timeout: 10),
            app.debugDescription
        )

        list.swipeUp()
        // 减速途中按下手指（0.4s 长按避免触发整行回复按钮），列表应立即停止滚动。
        list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
            .press(forDuration: 0.4)

        let marker = list.cells.element(boundBy: 2)
        XCTAssertTrue(marker.waitForExistence(timeout: 5), app.debugDescription)
        let marker2 = list.cells.element(boundBy: 5)
        XCTAssertTrue(marker2.waitForExistence(timeout: 5), app.debugDescription)
        Thread.sleep(forTimeInterval: 0.15)
        let firstFrame = marker.frame
        let secondMarkerFirstFrame = marker2.frame
        Thread.sleep(forTimeInterval: 0.8)
        let secondFrame = marker.frame
        let secondMarkerSecondFrame = marker2.frame
        XCTAssertEqual(
            secondFrame.minY,
            firstFrame.minY,
            accuracy: 2,
            "touch during deceleration must stop the comment list"
        )
        // 行间相对距离必须不变——行高在滚动中反复修正会让评论互相挤动。
        let firstDistance = secondMarkerFirstFrame.minY - firstFrame.minY
        let secondDistance = secondMarkerSecondFrame.minY - secondFrame.minY
        XCTAssertEqual(
            secondDistance,
            firstDistance,
            accuracy: 2,
            "relative positions between comments must not change after scrolling"
        )
    }

    @MainActor
    func testCommentsUIKitListRowsStableAfterRoundTrip() {
        let app = launchVideoDetail(
            waitForDetailMarker: false,
            extraArguments: ["--ui-test-comment-pagination"]
        )
        let toolbar = element("video.detail.toolbar-picker", in: app).firstMatch
        XCTAssertTrue(toolbar.waitForExistence(timeout: 15))
        toolbar.buttons["评论"].tap()

        let list = openCommentsTab(in: app)
        XCTAssertTrue(
            list.buttons["详情评论 1"].firstMatch.waitForExistence(timeout: 10),
            app.debugDescription
        )

        // 行间距与滚动偏移无关：下滑两屏再滑回，同两条评论的间距必须不变
        // （行高冻结则间距恒定；行高被重新计算则会变化）。只在两条评论同时
        // 可见时取 frame（列表作用域查询），避免离屏/隐藏元素污染测量。
        func visibleDistance() -> CGFloat? {
            let itemA = list.buttons["详情评论 1"].firstMatch
            let itemB = list.buttons["详情评论 3"].firstMatch
            guard itemA.exists, itemA.isHittable, itemB.exists, itemB.isHittable else {
                return nil
            }
            return itemB.frame.minY - itemA.frame.minY
        }

        XCTAssertTrue(
            list.buttons["详情评论 1"].firstMatch.waitForExistence(timeout: 10),
            app.debugDescription
        )
        guard let initialDistance = visibleDistance() else {
            XCTFail("markers 1 and 3 must be initially visible")
            return
        }

        list.swipeUp()
        list.swipeUp()
        var returnedDistance: CGFloat?
        for _ in 0..<8 where returnedDistance == nil {
            list.swipeDown()
            returnedDistance = visibleDistance()
        }
        let distance = returnedDistance ?? visibleDistance()
        XCTAssertNotNil(distance, "markers must be visible again after scrolling back")
        if let distance {
            XCTAssertEqual(
                distance, initialDistance, accuracy: 2,
                "distance between comments must not change after scrolling away and back"
            )
        }
    }


    @MainActor
    func testCommentsUIKitListLikesCommentInline() {
        let app = launchVideoDetail(waitForDetailMarker: false)
        let toolbar = element("video.detail.toolbar-picker", in: app).firstMatch
        XCTAssertTrue(toolbar.waitForExistence(timeout: 15))
        toolbar.buttons["评论"].tap()

        XCTAssertTrue(
            element("评论用户", in: app).firstMatch.waitForExistence(timeout: 10),
            app.debugDescription
        )
        // 点赞按钮依赖 `commentLikeTarget` 环境；缺失时会退化成不可点的角标。
        let likeButton = app.buttons["点赞评论"].firstMatch
        XCTAssertTrue(likeButton.waitForExistence(timeout: 10), app.debugDescription)
        // 未登录时点击应弹出提示而不是崩溃——同时验证 cell 里注入的
        // `dependencies` / `libraryStore` 环境对象可用。
        likeButton.tap()
        let alert = app.alerts["评论点赞"].firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5), app.debugDescription)
        alert.buttons["好"].tap()
    }

    @MainActor
    func testVideoDetailCommentSortUsesNativeSegmentedControl() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-reset-state", "--start-tab", "home",
            "--ui-test-video-detail-network", "--ui-test-player-controls-persistent",
            "--start-bvid", "BV1xx411c7mD",
        ]
        app.launch()
        let toolbar = element("video.detail.toolbar-picker", in: app).firstMatch
        XCTAssertTrue(toolbar.waitForExistence(timeout: 15))
        toolbar.buttons["评论"].tap()
        let sort = app.segmentedControls["评论排序"].firstMatch
        XCTAssertTrue(sort.waitForExistence(timeout: 15), app.debugDescription)
        let latest = sort.buttons["最新"]
        let hot = sort.buttons["最热"]
        XCTAssertTrue(latest.waitForExistence(timeout: 5))
        XCTAssertTrue(hot.isSelected)
        latest.tap()
        XCTAssertTrue(latest.isSelected)
        hot.tap()
        XCTAssertTrue(hot.isSelected)
    }


    @MainActor
    func testDisconnectedNoticeVisibleInPausedRealPlayerHost() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-reset-state",
            "-cc.bili.videoDetail.autoplayEnabled.v1", "NO",
            "--start-tab", "home",
            "--ui-test-video-detail-network", "--ui-test-player-controls-persistent",
            "--ui-test-player-offline",
            "--start-bvid", "BV1xx411c7mD",
        ]
        app.launch()
        let frame = app.descendants(matching: .any)["ui.videoDetail.playerFrame"].firstMatch
        XCTAssertTrue(frame.waitForExistence(timeout: 15))
        let notice = app.descendants(matching: .any)["player.network.disconnected"].firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(notice.label.contains("网络已断开"))
        XCTAssertGreaterThan(notice.frame.width, 0)
        XCTAssertGreaterThan(notice.frame.height, 0)
        XCTAssertTrue(frame.frame.intersects(notice.frame))
        let progress = app.descendants(matching: .any)["ui.player.progress"].firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(notice.frame.maxY, progress.frame.minY - 4)
        XCTAssertTrue(frame.frame.contains(notice.frame))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Disconnected notice in paused player"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testDanmakuSettingsSheetPresentsAndDismisses() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "danmaku"]
        app.launch()
        XCTAssertTrue(element("ui.videoDetail.ready", in: app).waitForExistence(timeout: 5))

        let showSettings = app.buttons["ui.videoDetail.danmakuSettings"]
        XCTAssertTrue(showSettings.waitForExistence(timeout: 2))
        showSettings.tap()

        let sheet = element("ui.videoDetail.sheet.danmakuSettings", in: app)
        XCTAssertTrue(sheet.waitForExistence(timeout: 2))

        let done = app.buttons["ui.videoDetail.sheet.danmakuSettings.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 2))
        done.tap()
        XCTAssertFalse(sheet.waitForExistence(timeout: 2))
    }

    @MainActor
    func testDanmakuDisplayAreaPersistsAcrossRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-fixture", "danmaku",
            "--ui-test-reset-state",
        ]
        app.launch()
        XCTAssertTrue(element("ui.videoDetail.ready", in: app).waitForExistence(timeout: 5))

        let initialValue = element("ui.videoDetail.danmakuSettings.persistedValue", in: app).label
        app.buttons["ui.videoDetail.danmakuSettings"].tap()
        let areaSlider = app.sliders["DanmakuKit 弹幕显示区域"]
        XCTAssertTrue(areaSlider.waitForExistence(timeout: 2))
        areaSlider.adjust(toNormalizedSliderPosition: 1.0)
        app.buttons["ui.videoDetail.sheet.danmakuSettings.done"].tap()

        let persisted = element("ui.videoDetail.danmakuSettings.persistedValue", in: app)
        XCTAssertTrue(persisted.waitForExistence(timeout: 2))
        let selectedValue = persisted.label
        XCTAssertNotEqual(selectedValue, initialValue, "Slider must actually change the saved setting")

        app.terminate()
        app.launchArguments = ["--ui-test-fixture", "danmaku"]
        app.launch()
        let restored = element("ui.videoDetail.danmakuSettings.persistedValue", in: app)
        XCTAssertTrue(restored.waitForExistence(timeout: 5))
        XCTAssertEqual(restored.label, selectedValue)
    }

    @MainActor
    func testVideoDetailUsesLayeredPagesAndToolbarPicker() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-reset-state",
            "--start-tab", "home",
            "--ui-test-video-detail-network", "--ui-test-player-controls-persistent",
            "--start-bvid", "BV1xx411c7mD",
        ]
        app.launch()

        let picker = element("video.detail.toolbar-picker", in: app).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        XCTAssertEqual(picker.buttons.count, 2)
        XCTAssertEqual(picker.frame.width, 180, accuracy: 2)
        // Native segmented controls use their intrinsic height on the active iOS.
        for button in picker.buttons.allElementsBoundByIndex {
            XCTAssertGreaterThan(button.frame.height, 0)
            XCTAssertGreaterThanOrEqual(button.frame.minY, picker.frame.minY - 1)
            XCTAssertLessThanOrEqual(button.frame.maxY, picker.frame.maxY + 1)
        }
        let appFrame = app.windows.firstMatch.frame
        let pickerFrame = picker.frame
        XCTAssertGreaterThanOrEqual(pickerFrame.minX, appFrame.minX)
        XCTAssertGreaterThanOrEqual(pickerFrame.minY, appFrame.minY)
        XCTAssertLessThanOrEqual(pickerFrame.maxX, appFrame.maxX)
        XCTAssertLessThanOrEqual(pickerFrame.maxY, appFrame.maxY)
        XCTAssertGreaterThan(appFrame.maxY - pickerFrame.maxY, 0)
        XCTAssertTrue(picker.isHittable)
        let detailButton = picker.buttons["简介"]
        let commentsButton = picker.buttons["评论"]

        let detailMarker = app.staticTexts["相关推荐"].firstMatch
        XCTAssertTrue(detailMarker.waitForExistence(timeout: 10))
        let summary = app.descendants(matching: .any)["video.detail.summary"].firstMatch
        XCTAssertTrue(summary.exists)
        XCTAssertGreaterThanOrEqual(picker.frame.minY, summary.frame.maxY - 1)
        XCTAssertGreaterThan(picker.frame.minY, appFrame.midY)
        let initialDetailMarkerY = detailMarker.frame.minY
        let detailScroll = app.scrollViews.containing(.staticText, identifier: "相关推荐").firstMatch
        XCTAssertTrue(detailScroll.waitForExistence(timeout: 5))
        let contentStart = app.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: detailScroll.frame.midX, dy: picker.frame.minY - 40)
        )
        let contentEnd = contentStart.withOffset(CGVector(dx: 0, dy: -180))
        contentStart.press(forDuration: 0.1, thenDragTo: contentEnd)
        let contentMoved = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in detailMarker.frame.minY < initialDetailMarkerY - 4 },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [contentMoved], timeout: 5), .completed)
        let scrolledDetailMarkerY = detailMarker.frame.minY
        XCTAssertLessThan(scrolledDetailMarkerY, initialDetailMarkerY)
        XCTAssertTrue(picker.isHittable)
        let scrolledAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        scrolledAttachment.name = "Portrait floating bottom toolbar after scrolling"
        scrolledAttachment.lifetime = .keepAlways
        add(scrolledAttachment)
        XCTAssertEqual(picker.frame.minY, pickerFrame.minY, accuracy: 2)

        commentsButton.tap()
        let commentHeader = element("comments.header", in: app).firstMatch
        XCTAssertTrue(commentHeader.waitForExistence(timeout: 5))
        XCTAssertTrue(commentHeader.isHittable)
        let hiddenSummary = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                let summary = app.descendants(matching: .any)["video.detail.summary"].firstMatch
                return (!summary.exists || !summary.isHittable)
                    && (!detailMarker.exists || !detailMarker.isHittable)
            }, object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [hiddenSummary], timeout: 5), .completed, app.debugDescription)
        detailButton.tap()
        XCTAssertTrue(detailMarker.waitForExistence(timeout: 5))
        XCTAssertEqual(detailMarker.frame.minY, scrolledDetailMarkerY, accuracy: 8)

        app.swipeRight()
        let homeTab = app.buttons["首页"].firstMatch
        XCTAssertTrue(homeTab.waitForExistence(timeout: 5))
        XCTAssertTrue(homeTab.isHittable)
        XCTAssertTrue(picker.waitForNonExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    func testVideoDetailToolbarCommentComposerIsAvailableByDefault() throws {
        let app = launchVideoDetail()
        let composeButton = app.buttons["video.detail.toolbar-comment"]
        XCTAssertTrue(composeButton.waitForExistence(timeout: 10))

        guard app.staticTexts["正在加载"].firstMatch.waitForNonExistence(timeout: 15) else {
            throw XCTSkip("在线详情尚未加载，无法取得评论目标；隔离数据的评论输入弹窗另有回归测试。")
        }

        let hittable = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: composeButton)
        wait(for: [hittable], timeout: 5)
        composeButton.tap()

        XCTAssertTrue(
            app.textViews["dynamic.comment.composer.editor"].waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testVideoDetailInteractiveScrollCollapseDoesNotResizeLandscapeVideo() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-reset-state",
            "--start-tab", "home",
            "--ui-test-video-detail-network", "--ui-test-player-controls-persistent",
            "--start-bvid", "BV1xx411c7mD",
        ]
        app.launch()

        let playerFrame = app.descendants(matching: .any)["ui.videoDetail.playerFrame"].firstMatch
        XCTAssertTrue(playerFrame.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["相关推荐"].waitForExistence(timeout: 10))
        let initialFrame = playerFrame.frame

        app.swipeUp()

        let playerStayedAtStandardHeight = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                abs(playerFrame.frame.height - initialFrame.height) < 1
            },
            object: nil
        )
        let result = XCTWaiter.wait(for: [playerStayedAtStandardHeight], timeout: 3)
        XCTAssertEqual(
            result,
            .completed,
            "landscape video should keep its standard player frame; initial=\(initialFrame) final=\(playerFrame.frame)"
        )
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Landscape video remains at standard height after scroll"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testVideoDetailInteractiveCollapseMovesContentWithPlayerBeforeContentScroll() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-reset-state",
            "-cc.bili.videoDetail.autoplayEnabled.v1", "NO",
            "--start-tab", "home",
            "--ui-test-video-detail-network", "--ui-test-player-controls-persistent",
            "--start-bvid", "BV1xx411c7mD",
        ]
        app.launch()

        let playerFrame = app.descendants(matching: .any)["ui.videoDetail.playerFrame"].firstMatch
        let detailMarker = app.staticTexts["相关推荐"].firstMatch
        XCTAssertTrue(playerFrame.waitForExistence(timeout: 10))
        XCTAssertTrue(detailMarker.waitForExistence(timeout: 10))

        let playerSurface = app.descendants(matching: .any)["ui.player.surface"].firstMatch
        XCTAssertTrue(playerSurface.waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
        let pauseButton = app.buttons["暂停"].firstMatch
        if pauseButton.waitForExistence(timeout: 2) {
            pauseButton.tap()
        }

        let initialPlayerFrame = playerFrame.frame
        let initialDetailMarkerFrame = detailMarker.frame
        print("interactive collapse initial player=\(initialPlayerFrame) detail=\(initialDetailMarkerFrame)")
        let scrollView = app.scrollViews.firstMatch
        XCTAssertTrue(scrollView.waitForExistence(timeout: 5))
        let dragStart = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.68))
        let dragEnd = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.64))
        dragStart.press(
            forDuration: 0.8,
            thenDragTo: dragEnd,
            withVelocity: .slow,
            thenHoldForDuration: 0.2
        )

        let playerCollapsed = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                playerFrame.frame.height < initialPlayerFrame.height - 4
            },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [playerCollapsed], timeout: 3), .completed)

        let playerCollapseDistance = initialPlayerFrame.height - playerFrame.frame.height
        let contentMoveDistance = initialDetailMarkerFrame.minY - detailMarker.frame.minY
        print(
            "interactive collapse after player=\(playerFrame.frame) detail=\(detailMarker.frame) "
                + "playerDelta=\(playerCollapseDistance) contentDelta=\(contentMoveDistance)"
        )
        XCTAssertEqual(
            contentMoveDistance,
            playerCollapseDistance,
            accuracy: 2,
            "content should move with the player before its minimum height is reached"
        )

        let settledDetailMarkerFrame = detailMarker.frame
        scrollView.swipeUp()
        let minimumPlayer = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                playerFrame.frame.height <= 55
            },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [minimumPlayer], timeout: 3), .completed)
        XCTAssertLessThan(
            detailMarker.frame.minY,
            settledDetailMarkerFrame.minY - 4,
            "content should start relative scrolling only after the player reaches minimum height"
        )
        XCTAssertEqual(playerFrame.frame.height, 54, accuracy: 1)
    }

    @MainActor
    func testVideoDetailInteractiveCollapseMovesCommentSectionWithPlayerBeforeCommentScroll() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-reset-state",
            "-cc.bili.videoDetail.autoplayEnabled.v1", "NO",
            "--start-tab", "home",
            "--ui-test-video-detail-network", "--ui-test-player-controls-persistent",
            "--start-bvid", "BV1xx411c7mD",
        ]
        app.launch()

        let picker = element("video.detail.toolbar-picker", in: app).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        let commentsButton = picker.buttons["评论"]
        XCTAssertTrue(commentsButton.waitForExistence(timeout: 5))
        commentsButton.tap()

        let playerFrame = app.descendants(matching: .any)["ui.videoDetail.playerFrame"].firstMatch
        let commentHeader = element("comments.header", in: app).firstMatch
        XCTAssertTrue(playerFrame.waitForExistence(timeout: 5))
        XCTAssertTrue(commentHeader.waitForExistence(timeout: 10))

        let initialPlayerFrame = playerFrame.frame
        let initialCommentHeaderFrame = commentHeader.frame
        XCTAssertGreaterThanOrEqual(
            initialCommentHeaderFrame.minY,
            initialPlayerFrame.maxY - 1,
            "pausing at the scroll origin must not place the comment header under the player"
        )
        let initialAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        initialAttachment.name = "Paused comment section begins below player"
        initialAttachment.lifetime = .keepAlways
        add(initialAttachment)
        let scrollView = app.tables["comments.list"].firstMatch
        XCTAssertTrue(scrollView.waitForExistence(timeout: 5), app.debugDescription)

        // Use absolute screen coordinates: the header itself moves while the
        // player collapses. A short press also avoids long-press reply actions.
        func dragHeader(up distance: CGFloat) {
            let frame = commentHeader.frame
            let start = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: frame.midX, dy: frame.midY))
            start.press(
                forDuration: 0.05,
                thenDragTo: start.withOffset(CGVector(dx: 0, dy: -distance)),
                withVelocity: .slow,
                thenHoldForDuration: 1.0
            )
        }
        dragHeader(up: 32)

        let playerCollapsed = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                playerFrame.frame.height < initialPlayerFrame.height - 4
            },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [playerCollapsed], timeout: 3), .completed)

        let playerCollapseDistance = initialPlayerFrame.height - playerFrame.frame.height
        let commentMoveDistance = initialCommentHeaderFrame.minY - commentHeader.frame.minY
        print(
            "interactive comment collapse initialPlayer=\(initialPlayerFrame) "
                + "currentPlayer=\(playerFrame.frame) initialHeader=\(initialCommentHeaderFrame) "
                + "currentHeader=\(commentHeader.frame)"
        )
        let partialAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        partialAttachment.name = "Comment section follows player during collapse"
        partialAttachment.lifetime = .keepAlways
        add(partialAttachment)
        XCTAssertEqual(
            commentMoveDistance,
            playerCollapseDistance,
            accuracy: 2,
            "comment section should move with the player before the player reaches minimum height"
        )

        XCTAssertGreaterThan(
            playerFrame.frame.height, 54,
            "the initial small drag must verify coupling before the player reaches minimum height"
        )
        // Collapse using the inert header, not a comment row. Fixed 24/8-point
        // steps assumed a one-to-one pan distance and could tap a reply or fail
        // to cross UIScrollView's drag threshold near the minimum.
        for _ in 0..<3 {
            let remainingCollapse = playerFrame.frame.height - 54
            if remainingCollapse <= 1 { break }
            dragHeader(up: remainingCollapse + 16)
        }
        let minimumPlayer = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                playerFrame.frame.height <= 55
            },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [minimumPlayer], timeout: 3), .completed)
        let headerAtMinimum = commentHeader.frame
        // The header may already be above the visible area after the boundary
        // crossing. Start the continuation inside the visible scroll viewport,
        // never at the off-screen header (which can hit the status bar).
        let viewport = scrollView.frame
        let continuationStart = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: viewport.midX, dy: viewport.minY + viewport.height * 0.65))
        continuationStart.press(
            forDuration: 0.05,
            thenDragTo: continuationStart.withOffset(CGVector(dx: 0, dy: -32)),
            withVelocity: .slow,
            thenHoldForDuration: 1.0
        )
        XCTAssertLessThan(
            commentHeader.frame.minY,
            headerAtMinimum.minY - 4,
            "comment content should start relative scrolling only after the player reaches minimum height"
        )
        let minimumAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        minimumAttachment.name = "Comment section scrolls after player minimum"
        minimumAttachment.lifetime = .keepAlways
        add(minimumAttachment)
        XCTAssertEqual(playerFrame.frame.height, 54, accuracy: 1)
        XCTAssertTrue(commentHeader.exists)
    }

    @MainActor
    func testVideoDetailPlayerFullscreenRoundTripKeepsDetailShellMounted() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-reset-state",
            "--start-tab", "home",
            "--ui-test-video-detail-network", "--ui-test-player-controls-persistent",
            "--start-bvid", "BV1xx411c7mD",
        ]
        app.launch()

        let picker = element("video.detail.toolbar-picker", in: app).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 10))

        revealPlayerControls(in: app)
        let fullscreen = fullscreenControl(in: app)
        XCTAssertTrue(fullscreen.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForVisiblePlayerControl(in: app, { fullscreenControl(in: app) }, timeout: 5))
        XCTAssertFalse(app.buttons["ui.player.back"].exists)
        let portraitAttachment = XCTAttachment(screenshot: app.screenshot())
        portraitAttachment.name = "Geometry portrait before fullscreen"
        portraitAttachment.lifetime = .keepAlways
        add(portraitAttachment)
        tapPlayerControl(fullscreen, in: app)

        XCUIDevice.shared.orientation = .landscapeLeft
        let landscapeWindow = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                let frame = app.windows.firstMatch.frame
                return frame.width > frame.height
            },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [landscapeWindow], timeout: 10), .completed)
        let diagnostics = app.descendants(matching: .any)["ui.videoDetail.rotationDiagnostics"].firstMatch
        let completedRotation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                (diagnostics.value as? String ?? "").contains("landscape")
            },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [completedRotation], timeout: 10), .completed)
        XCTAssertFalse(picker.waitForExistence(timeout: 2))
        if !waitForVisiblePlayerControl(in: app, { fullscreenControl(in: app) }, timeout: 2) {
            let surface = app.buttons["ui.player.surface"]
            XCTAssertTrue(surface.waitForExistence(timeout: 5))
            surface.tap()
        }
        XCTAssertTrue(waitForVisiblePlayerControl(in: app, { fullscreenControl(in: app) }, timeout: 5))
        let fullscreenTime = app.descendants(matching: .any)
            .matching(identifier: "video.fullscreen.status.time")
            .firstMatch
        let fullscreenBattery = app.descendants(matching: .any)
            .matching(identifier: "video.fullscreen.status.battery")
            .firstMatch
        let fullscreenProgress = app.descendants(matching: .any)
            .matching(identifier: "ui.player.progress")
            .firstMatch
        XCTAssertTrue(fullscreenTime.waitForExistence(timeout: 5))
        XCTAssertTrue(fullscreenBattery.waitForExistence(timeout: 5))
        XCTAssertTrue(fullscreenProgress.waitForExistence(timeout: 5))
        let landscapeFrame = app.windows.firstMatch.frame
        XCTAssertLessThan(fullscreenTime.frame.midX, landscapeFrame.midX)
        XCTAssertGreaterThan(fullscreenBattery.frame.midX, landscapeFrame.midX)
        XCTAssertLessThan(fullscreenTime.frame.minY, landscapeFrame.minY + landscapeFrame.height * 0.25)
        XCTAssertLessThan(fullscreenBattery.frame.minY, landscapeFrame.minY + landscapeFrame.height * 0.25)
        XCTAssertEqual(fullscreenTime.frame.midY, fullscreenBattery.frame.midY, accuracy: 2)
        XCTAssertEqual(fullscreenTime.frame.minX, fullscreenProgress.frame.minX, accuracy: 2)
        XCTAssertEqual(fullscreenBattery.frame.maxX, fullscreenProgress.frame.maxX, accuracy: 2)
        let landscapeAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        landscapeAttachment.name = "Geometry landscape after fullscreen"
        landscapeAttachment.lifetime = .keepAlways
        add(landscapeAttachment)
        XCTAssertFalse(app.buttons["ui.player.back"].exists)
        let landscapeExit = fullscreenControl(in: app)
        tapPlayerControl(landscapeExit, in: app)
        XCUIDevice.shared.orientation = .portrait

        let portraitWindow = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                let frame = app.windows.firstMatch.frame
                return frame.height > frame.width
            },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [portraitWindow], timeout: 10), .completed)
        let statusControlsHidden = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                !fullscreenTime.exists && !fullscreenBattery.exists
            },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [statusControlsHidden], timeout: 5), .completed)
        let detailMarker = app.staticTexts["相关推荐"].firstMatch
        XCTAssertTrue(detailMarker.waitForExistence(timeout: 5))
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
    }


    @MainActor
    func testCoinSheetExplainsAutomaticLikeBeforeSubmission() {
        let app = launchVideoDetail(waitForDetailMarker: false)
        let coin = app.buttons.matching(NSPredicate(format: "label == %@", "投币")).firstMatch
        XCTAssertTrue(coin.waitForExistence(timeout: 10), app.debugDescription)
        for _ in 0..<3 where !coin.isHittable { app.swipeDown() }
        XCTAssertTrue(coin.isHittable, app.debugDescription)
        coin.tap()
        let notice = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "投币时同时点赞")).firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["投 1 枚"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["投 1 枚"].isHittable)
    }

    @MainActor
    func testAutomaticRecoveryTestBlocksShortVideo() {
        let app = launchVideoDetail(waitForDetailMarker: false, extraArguments: ["-cc.bili.playback.showsRecoveryTestEntry.v1", "YES"])
        openAutomaticRecoveryTest(in: app)
        let start = app.buttons["recovery.test.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertFalse(start.isEnabled)
        XCTAssertFalse(app.buttons["recovery.test.startBoundary"].isEnabled)
        XCTAssertTrue(app.staticTexts["请选择至少5分钟的普通视频。"].exists)
    }

    @MainActor
    func testAutomaticRecoveryEntryHiddenWhenDisabled() {
        let app = launchVideoDetail(waitForDetailMarker: false,
                                    extraArguments: ["-cc.bili.playback.showsRecoveryTestEntry.v1", "NO"])
        revealPlayerControls(in: app)
        let more = app.buttons["ui.player.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        tapPlayerControl(more, in: app)
        XCTAssertTrue(app.navigationBars["播放设置"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["recovery.test.open"].exists)
    }

    @MainActor
    func testRecoveryEntrySettingPersistsAndControlsPlayerMenu() {
        let app = XCUIApplication()
        app.launchArguments = ["-cc.bili.display.visibleRootTabs.v1", "(home,mine)", "--start-tab", "mine"]
        app.launch()
        let diagnostics = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "开发者与诊断")).firstMatch
        for _ in 0..<8 where !diagnostics.isHittable { app.swipeUp() }
        XCTAssertTrue(diagnostics.isHittable, app.debugDescription)
        diagnostics.tap()
        let setting = app.switches["mine.diagnostics.recoveryTestEntry"]
        XCTAssertTrue(setting.waitForExistence(timeout: 5), app.debugDescription)
        if setting.value as? String != "1" {
            setting.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        XCTAssertEqual(setting.value as? String, "1")
        app.terminate()

        app.launchArguments = ["--start-tab", "home", "--ui-test-video-detail-network",
                               "--ui-test-player-controls-persistent", "--start-bvid", "BV1xx411c7mD"]
        app.launch()
        XCTAssertTrue(element("video.detail.toolbar-picker", in: app).firstMatch.waitForExistence(timeout: 15))
        revealPlayerControls(in: app)
        tapPlayerControl(app.buttons["ui.player.more"], in: app)
        XCTAssertTrue(app.buttons["recovery.test.open"].waitForExistence(timeout: 5))
        app.terminate()

        app.launchArguments = ["-cc.bili.display.visibleRootTabs.v1", "(home,mine)", "--start-tab", "mine"]
        app.launch()
        for _ in 0..<8 where !diagnostics.isHittable { app.swipeUp() }
        XCTAssertTrue(diagnostics.isHittable)
        diagnostics.tap()
        XCTAssertTrue(setting.waitForExistence(timeout: 5))
        XCTAssertEqual(setting.value as? String, "1")
        setting.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(setting.value as? String, "0")
    }

    @MainActor
    func testAutomaticRecoveryTestStopsAndCopiesPartialReport() {
        let app = launchVideoDetail(waitForDetailMarker: false,
                                    extraArguments: ["--ui-test-recovery-long-video", "-cc.bili.playback.showsRecoveryTestEntry.v1", "YES"])
        openAutomaticRecoveryTest(in: app)
        let start = app.buttons["recovery.test.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertTrue(start.isEnabled, app.debugDescription)
        start.tap()
        let stop = app.buttons["recovery.test.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 10))
        stop.tap()
        let result = app.staticTexts["recovery.test.result"]
        if !result.exists { app.swipeUp() }
        XCTAssertTrue(result.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(result.label.contains("中断"))
        let copy = app.buttons["recovery.test.copy"]
        if !copy.isHittable { app.swipeUp() }
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        copy.tap()
        XCTAssertTrue(app.buttons["已复制测试报告"].waitForExistence(timeout: 5))
        XCTAssertFalse(stop.exists)
    }

    @MainActor
    func testAutomaticRecoveryBoundaryShortTestStopsAndCopiesReport() {
        let app = launchVideoDetail(waitForDetailMarker: false,
                                    extraArguments: ["--ui-test-recovery-long-video", "-cc.bili.playback.showsRecoveryTestEntry.v1", "YES"])
        openAutomaticRecoveryTest(in: app)
        let start = app.buttons["recovery.test.startBoundary"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertTrue(start.isEnabled, app.debugDescription)
        start.tap()
        let stop = app.buttons["recovery.test.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 10))
        stop.tap()
        let result = app.staticTexts["recovery.test.result"]
        if !result.exists { app.swipeUp() }
        XCTAssertTrue(result.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(result.label.contains("中断"))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "/3 项")).firstMatch.exists)
        let copy = app.buttons["recovery.test.copy"]
        if !copy.isHittable { app.swipeUp() }
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        copy.tap()
        XCTAssertTrue(app.buttons["已复制测试报告"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func openAutomaticRecoveryTest(in app: XCUIApplication) {
        revealPlayerControls(in: app)
        let more = app.buttons["ui.player.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        tapPlayerControl(more, in: app)
        let entry = app.buttons["recovery.test.open"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        for _ in 0..<4 where !entry.isHittable { app.swipeUp() }
        XCTAssertTrue(entry.isHittable, app.debugDescription)
        entry.tap()
    }

    @MainActor
    func testVideoDetailQualitySwitchKeepsPlayerSurfaceMounted() {
        let app = launchVideoDetail(waitForDetailMarker: false)
        revealPlayerControls(in: app)
        let more = app.buttons["ui.player.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        tapPlayerControl(more, in: app)

        let quality = app.descendants(matching: .any)["ui.player.quality"].firstMatch
        XCTAssertTrue(quality.waitForExistence(timeout: 5))
        quality.tap()

        let qualityTitle = app.navigationBars["清晰度"]
        XCTAssertTrue(qualityTitle.waitForExistence(timeout: 5))
        let choice = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "720P")).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        choice.tap()

        revealPlayerControls(in: app)
        XCTAssertTrue(fullscreenControl(in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["相关推荐"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testVideoDetailMoreControlsToggleBackgroundPlayback() {
        let app = launchVideoDetail(waitForDetailMarker: false)
        revealPlayerControls(in: app)
        let more = app.buttons["ui.player.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        tapPlayerControl(more, in: app)

        let backgroundPlayback = app.switches["ui.player.backgroundPlayback"]
        XCTAssertTrue(backgroundPlayback.waitForExistence(timeout: 5))
        XCTAssertEqual(backgroundPlayback.value as? String, "0")

        backgroundPlayback.coordinate(
            withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)
        ).tap()
        let backgroundPlaybackEnabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "1"),
            object: backgroundPlayback
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [backgroundPlaybackEnabled], timeout: 3),
            .completed
        )
    }

    @MainActor
    func testVideoDetailDanmakuInteractionKeepsPlayerSurfaceMounted() {
        let app = launchVideoDetail(waitForDetailMarker: false)
        revealPlayerControls(in: app)
        let more = app.buttons["ui.player.more"]
        XCTAssertTrue(waitForVisiblePlayerControl(in: app, { app.buttons["ui.player.more"] }, timeout: 5))
        tapPlayerControl(more, in: app)
        let settings = app.buttons["弹幕设置"]
        if !settings.waitForExistence(timeout: 3) {
            revealPlayerControls(in: app)
            XCTAssertTrue(waitForVisiblePlayerControl(in: app, { app.buttons["ui.player.more"] }, timeout: 5))
            tapPlayerControl(app.buttons["ui.player.more"], in: app)
        }
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()

        XCTAssertTrue(app.staticTexts["相关推荐"].waitForExistence(timeout: 5))
        revealPlayerControls(in: app)
        XCTAssertTrue(fullscreenControl(in: app).exists)
    }

    @MainActor
    func testVideoDetailRapidRotationPublishesStableIdentityDiagnostics() {
        let app = launchVideoDetail(waitForDetailMarker: false)
        revealPlayerControls(in: app)
        let fullscreen = fullscreenControl(in: app)
        XCTAssertTrue(fullscreen.waitForExistence(timeout: 5))

        tapPlayerControl(fullscreen, in: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCUIDevice.shared.orientation = .portrait
        XCUIDevice.shared.orientation = .landscapeRight
        XCUIDevice.shared.orientation = .portrait

        let diagnostics = app.descendants(matching: .any)["ui.videoDetail.rotationDiagnostics"].firstMatch
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 15))
        let value = diagnostics.value as? String ?? ""
        print("rotationDiagnostics=\(value)")
        XCTAssertTrue(value.contains("playerViewModelIdentity"))
        XCTAssertTrue(value.contains("surfaceIdentity"))
        XCTAssertTrue(value.contains("surfaceAttachCount"))
        XCTAssertTrue(value.contains("surfaceDetachCount"))
        XCTAssertTrue(value.contains("playbackState"))
        XCTAssertTrue(value.contains("isBuffering"))
        XCTAssertTrue(app.staticTexts["相关推荐"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testVideoDetailRotationDuringInitialBufferingRecoversPlaybackSurface() {
        let app = launchVideoDetail(waitForDetailMarker: false)
        revealPlayerControls(in: app)
        let fullscreen = fullscreenControl(in: app)
        XCTAssertTrue(fullscreen.waitForExistence(timeout: 5))

        tapPlayerControl(fullscreen, in: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCUIDevice.shared.orientation = .portrait

        XCTAssertTrue(app.staticTexts["相关推荐"].waitForExistence(timeout: 15))
        if !fullscreenControl(in: app).exists {
            app.buttons["ui.player.surface"].tap()
        }
        revealPlayerControls(in: app)
        XCTAssertTrue(fullscreenControl(in: app).waitForExistence(timeout: 5))
    }

    @MainActor
    func testVideoDetailBackgroundRecoveryKeepsPlayerSurfaceMounted() {
        let app = launchVideoDetail(waitForDetailMarker: false)
        XCUIDevice.shared.press(.home)
        sleep(1)
        app.activate()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(app.staticTexts["相关推荐"].waitForExistence(timeout: 10))
        let surface = app.buttons["ui.player.surface"]
        XCTAssertTrue(surface.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(surface.frame.width, 0)
        XCTAssertGreaterThan(surface.frame.height, 0)

        let fullscreen = fullscreenControl(in: app)
        if fullscreen.exists {
            XCTAssertTrue(waitForVisiblePlayerControl(in: app, { fullscreenControl(in: app) }, timeout: 5))
        }
    }

    @MainActor
    func testVideoDetailExitDuringRotationReturnsToHomeWithoutRebuildingPlayer() {
        let app = launchVideoDetail(waitForDetailMarker: false)
        revealPlayerControls(in: app)
        let fullscreen = fullscreenControl(in: app)
        XCTAssertTrue(fullscreen.waitForExistence(timeout: 5))

        tapPlayerControl(fullscreen, in: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCUIDevice.shared.orientation = .portrait

        XCTAssertTrue(app.staticTexts["相关推荐"].waitForExistence(timeout: 10))
        let portraitWindow = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                let frame = app.windows.firstMatch.frame
                return frame.height > frame.width
            }, object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [portraitWindow], timeout: 10), .completed)
        let homeTab = app.buttons["首页"].firstMatch
        for _ in 0..<2 where !homeTab.exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
                .press(
                    forDuration: 0.3,
                    thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
                )
        }
        XCTAssertTrue(homeTab.waitForExistence(timeout: 10))
        XCTAssertTrue(homeTab.isHittable)
    }

    @MainActor
    func testVideoDetailPausingAutoplayKeepsCommentOriginBelowPlayer() {
        verifyAutoplayCommentOrigin()
    }

    @MainActor
    func testVideoDetailStartingPausedKeepsCommentOrigin() {
        verifyAutoplayCommentOrigin(autoplayEnabled: false)
    }

    @MainActor
    func testVideoDetailBottomPlayStartsManualPlayback() {
        verifyAutoplayCommentOrigin(autoplayEnabled: false, manualStartIdentifier: "ui.player.playback.toggle")
    }

    @MainActor
    private func verifyAutoplayCommentOrigin(
        autoplayEnabled: Bool = true,
        manualStartIdentifier: String = "ui.player.playback.start"
    ) {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-reset-state",
            "-cc.bili.videoDetail.autoplayEnabled.v1", autoplayEnabled ? "YES" : "NO",
            "--start-tab", "home",
            "--ui-test-video-detail-network", "--ui-test-player-controls-persistent",
            "--start-bvid", "BV1xx411c7mD",
        ]
        app.launch()

        let picker = element("video.detail.toolbar-picker", in: app).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        picker.buttons["评论"].tap()

        let playerFrame = app.descendants(matching: .any)["ui.videoDetail.playerFrame"].firstMatch
        let commentHeader = element("comments.header", in: app).firstMatch
        XCTAssertTrue(playerFrame.waitForExistence(timeout: 10))
        XCTAssertTrue(commentHeader.waitForExistence(timeout: 10))
        let playingPlayerFrame = playerFrame.frame
        let playingHeaderFrame = commentHeader.frame

        revealPlayerControls(in: app)
        if !autoplayEnabled {
            let initialPlayButton = app.buttons[manualStartIdentifier]
            XCTAssertTrue(initialPlayButton.waitForExistence(timeout: 5))
            tapPlayerControl(initialPlayButton, in: app)
            revealPlayerControls(in: app)
            XCTAssertEqual(commentHeader.frame.minY, playingHeaderFrame.minY, accuracy: 1)
        }
        let pauseButton = app.buttons.matching(identifier: "ui.player.playback.toggle")
            .matching(NSPredicate(format: "label == %@", "暂停")).firstMatch
        XCTAssertTrue(pauseButton.waitForExistence(timeout: 10))
        tapPlayerControl(pauseButton, in: app)

        let playButton = app.buttons["播放"].firstMatch
        XCTAssertTrue(playButton.waitForExistence(timeout: 5))
        let pausedPlayerFrame = playerFrame.frame
        let pausedHeaderFrame = commentHeader.frame
        print(
            "autoplay pause origin playingPlayer=\(playingPlayerFrame) "
                + "playingHeader=\(playingHeaderFrame) pausedPlayer=\(pausedPlayerFrame) "
                + "pausedHeader=\(pausedHeaderFrame)"
        )
        let pausedAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        pausedAttachment.name = "Autoplay pause keeps comment origin below player"
        pausedAttachment.lifetime = .keepAlways
        add(pausedAttachment)
        XCTAssertGreaterThanOrEqual(playingHeaderFrame.minY, playingPlayerFrame.maxY + 8)
        XCTAssertGreaterThanOrEqual(pausedHeaderFrame.minY, pausedPlayerFrame.maxY + 8)
        XCTAssertEqual(pausedPlayerFrame.minY, playingPlayerFrame.minY, accuracy: 1)
        XCTAssertEqual(pausedPlayerFrame.height, playingPlayerFrame.height, accuracy: 1)
        XCTAssertEqual(pausedHeaderFrame.minY, playingHeaderFrame.minY, accuracy: 1)

        revealPlayerControls(in: app)
        XCTAssertTrue(playButton.waitForExistence(timeout: 5))
        tapPlayerControl(playButton, in: app)
        revealPlayerControls(in: app)
        XCTAssertTrue(app.buttons["暂停"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(commentHeader.frame.minY, playingHeaderFrame.minY, accuracy: 1)
        XCTAssertEqual(playerFrame.frame.height, playingPlayerFrame.height, accuracy: 1)
    }

    @MainActor
    private func fullscreenControl(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(
            format: "identifier == %@ OR label IN %@",
            "ui.player.fullscreen.toggle", ["全屏", "退出全屏"]
        )).firstMatch
    }

    @MainActor
    private func revealPlayerControls(in app: XCUIApplication) {
        let surface = app.buttons["ui.player.surface"].firstMatch
        XCTAssertTrue(surface.waitForExistence(timeout: 5))
        for _ in 0..<3 {
            if waitForVisiblePlayerControl(in: app, { fullscreenControl(in: app) }, timeout: 1) { return }
            surface.tap()
        }
        XCTAssertTrue(waitForVisiblePlayerControl(in: app, { fullscreenControl(in: app) }, timeout: 5), app.debugDescription)
    }

    // XCUI may reject the activation point of a visible SwiftUI glass button.
    // Check its enabled state and full on-screen bounds, then perform an actual
    // coordinate tap; each caller still verifies the resulting UI action.
    @MainActor
    private func waitForVisiblePlayerControl(
        in app: XCUIApplication,
        _ query: () -> XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let element = query()
            if element.exists,
               element.frame.width > 1,
               element.frame.height > 1,
               element.isEnabled,
               app.windows.firstMatch.frame.contains(element.frame) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        let element = query()
        return element.exists
            && element.frame.width > 1
            && element.frame.height > 1
            && element.isEnabled
            && app.windows.firstMatch.frame.contains(element.frame)
    }

    @MainActor
    private func tapPlayerControl(_ control: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        let frame = control.frame
        XCTAssertGreaterThan(frame.width, 1)
        XCTAssertGreaterThan(frame.height, 1)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(frame))
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// 旋转往返后评论区不得错位：内容区在全屏布局下冻结尺寸，评论表
    /// 宽度全程不变；回到竖屏后滚动位置与评论间距都必须复原。
    /// 出现"header 与首条评论之间大段空洞"即本用例失败。
    @MainActor
    func testCommentsUIKitListStableAfterFullscreenRoundTrip() {
        let app = launchVideoDetail(
            waitForDetailMarker: false,
            extraArguments: ["--ui-test-comment-pagination"]
        )
        let list = openCommentsTab(in: app)
        let sortControl = app.segmentedControls["评论排序"].firstMatch
        XCTAssertTrue(sortControl.waitForExistence(timeout: 10), app.debugDescription)
        let comment1 = list.buttons["详情评论 1"].firstMatch
        let comment3 = list.buttons["详情评论 3"].firstMatch
        XCTAssertTrue(comment1.waitForExistence(timeout: 10), app.debugDescription)

        func markerDistance() -> CGFloat? {
            guard comment1.exists, comment1.isHittable,
                  comment3.exists, comment3.isHittable else { return nil }
            return comment3.frame.minY - comment1.frame.minY
        }

        guard let initialMarkerDistance = markerDistance() else {
            XCTFail("comments 1 and 3 must be initially visible")
            return
        }

        // 下滑两屏（加载第二页、播放器收起）再进入横屏，模拟真实使用路径。
        list.swipeUp()
        list.swipeUp()
        let markerBeforeRotation = list.buttons["详情评论 5"].firstMatch
        XCTAssertTrue(
            markerBeforeRotation.waitForExistence(timeout: 10),
            "deeper comments must be loaded before rotation"
        )

        let playerToggle = app.buttons["ui.player.fullscreen.toggle"].firstMatch
        if !playerToggle.waitForExistence(timeout: 3) {
            // 控件浮层被隐藏时先点播放器画面唤起。
            app.buttons["ui.player.surface"].firstMatch.tap()
        }
        XCTAssertTrue(playerToggle.waitForExistence(timeout: 5), app.debugDescription)
        playerToggle.tap()
        // 等待系统转场、全屏布局与恢复稳定。
        Thread.sleep(forTimeInterval: 2.5)

        // 退出全屏：转场后控件浮层可能已隐藏，先点播放器画面唤起再点退出，
        // 最多重试三次。
        var exited = false
        let surface = app.buttons["ui.player.surface"].firstMatch
        for _ in 0..<3 where !exited {
            let exitToggle = app.buttons["ui.player.fullscreen.toggle"].firstMatch
            if exitToggle.waitForExistence(timeout: 3) {
                exitToggle.tap()
                exited = true
            } else {
                surface.tap()
            }
        }
        XCTAssertTrue(exited, "fullscreen exit control must be reachable in landscape")
        Thread.sleep(forTimeInterval: 2.0)
        XCUIDevice.shared.orientation = .portrait

        // 旋转后滚动位置必须保留：旋转前可见的评论仍应存在。
        XCTAssertTrue(
            markerBeforeRotation.waitForExistence(timeout: 10),
            "comment visible before rotation must still exist after round trip"
        )
        // 滑回顶部直到 1/3 两条评论重新同时可见，间距必须与旋转前一致。
        var restoredDistance: CGFloat?
        for _ in 0..<8 where restoredDistance == nil {
            list.swipeDown()
            restoredDistance = markerDistance()
        }
        guard let finalMarkerDistance = restoredDistance ?? markerDistance() else {
            XCTFail("comments 1 and 3 must be simultaneously visible after round trip")
            return
        }
        XCTAssertEqual(
            finalMarkerDistance, initialMarkerDistance, accuracy: 2,
            "distance between comments must not change after fullscreen round trip"
        )
    }

    /// 切换排序 = 内容整体替换：走 reloadData 语义后评论行间距与切换前
    /// 一致，且头部到首条评论不得出现大段空洞；最热↔最新往返均成立。
    @MainActor
    func testCommentsUIKitListStableAfterSortSwitches() {
        let app = launchVideoDetail(
            waitForDetailMarker: false,
            extraArguments: [
                "--ui-test-comment-pagination",
                "--ui-test-comment-sort-sentinel",
            ]
        )
        let list = openCommentsTab(in: app)
        let sortControl = app.segmentedControls["评论排序"].firstMatch
        XCTAssertTrue(sortControl.waitForExistence(timeout: 10), app.debugDescription)
        let hotFirstComment = list.buttons["回复 排序标记甲 的评论"].firstMatch
        let latestFirstComment = list.buttons["回复 排序标记乙 的评论"].firstMatch
        let comment3 = list.buttons["详情评论 3"].firstMatch
        XCTAssertTrue(hotFirstComment.waitForExistence(timeout: 10), app.debugDescription)

        func headerDistance(to firstComment: XCUIElement) -> CGFloat? {
            guard sortControl.exists, sortControl.isHittable,
                  firstComment.exists, firstComment.isHittable else { return nil }
            return firstComment.frame.minY - sortControl.frame.minY
        }
        func markerDistance(from firstComment: XCUIElement) -> CGFloat? {
            guard firstComment.exists, firstComment.isHittable,
                  comment3.exists, comment3.isHittable else { return nil }
            return comment3.frame.minY - firstComment.frame.minY
        }

        let initialHeaderY = sortControl.frame.minY
        guard let initialHeaderDistance = headerDistance(to: hotFirstComment),
              let initialMarkerDistance = markerDistance(from: hotFirstComment) else {
            XCTFail("header, first hot comment, and third comment must be initially visible")
            return
        }
        // The full-row reply button begins at the comment row top; with the current
        // header padding its gap from the picker origin is about 40–55pt.
        XCTAssertGreaterThanOrEqual(initialHeaderDistance, 35)
        XCTAssertLessThan(initialHeaderDistance, 65)
        let latest = sortControl.buttons["最新"].firstMatch
        let hot = sortControl.buttons["最热"].firstMatch

        latest.tap()
        XCTAssertTrue(
            sortControl.waitForExistence(timeout: 5) && sortControl.isHittable,
            "sort control must remain hittable immediately after switching to latest"
        )
        XCTAssertEqual(sortControl.frame.minY, initialHeaderY, accuracy: 2)
        XCTAssertTrue(
            hotFirstComment.waitForNonExistence(timeout: 2),
            "hot first comment must leave while the delayed latest response is loading"
        )
        XCTAssertFalse(latestFirstComment.exists, "latest result must still be loading")
        let skeleton = list.descendants(matching: .any)["comments.loading"].firstMatch
        XCTAssertTrue(skeleton.waitForExistence(timeout: 2))
        XCTAssertGreaterThanOrEqual(skeleton.frame.minY, sortControl.frame.maxY - 1)
        XCTAssertGreaterThan(skeleton.frame.height, 300)
        XCTAssertTrue(sortControl.isHittable, "sort control must stay hittable during latest loading")
        XCTAssertEqual(sortControl.frame.minY, initialHeaderY, accuracy: 2)
        XCTAssertTrue(
            latestFirstComment.waitForExistence(timeout: 10),
            "latest first comment must appear after the latest-sort request finishes"
        )
        XCTAssertTrue(sortControl.isHittable, "sort control must stay hittable after latest loads")
        XCTAssertEqual(sortControl.frame.minY, initialHeaderY, accuracy: 2)
        guard let latestHeaderDistance = headerDistance(to: latestFirstComment),
              let latestMarkerDistance = markerDistance(from: latestFirstComment) else {
            XCTFail("latest header and first comments must be visible without scrolling")
            return
        }
        XCTAssertEqual(latestHeaderDistance, initialHeaderDistance, accuracy: 4)
        XCTAssertLessThan(latestHeaderDistance, 70)
        XCTAssertEqual(latestMarkerDistance, initialMarkerDistance, accuracy: 2)

        hot.tap()
        XCTAssertTrue(
            sortControl.waitForExistence(timeout: 5) && sortControl.isHittable,
            "sort control must remain hittable immediately after switching back to hot"
        )
        XCTAssertEqual(sortControl.frame.minY, initialHeaderY, accuracy: 2)
        XCTAssertTrue(
            hotFirstComment.waitForExistence(timeout: 10),
            "hot first comment must reappear after the hot-sort request finishes"
        )
        XCTAssertTrue(sortControl.isHittable, "sort control must stay hittable after hot loads")
        XCTAssertEqual(sortControl.frame.minY, initialHeaderY, accuracy: 2)
        guard let hotHeaderDistance = headerDistance(to: hotFirstComment),
              let hotMarkerDistance = markerDistance(from: hotFirstComment) else {
            XCTFail("hot header and first comments must be visible without scrolling")
            return
        }
        XCTAssertEqual(hotHeaderDistance, initialHeaderDistance, accuracy: 4)
        XCTAssertLessThan(hotHeaderDistance, 70)
        XCTAssertEqual(hotMarkerDistance, initialMarkerDistance, accuracy: 2)
    }

    @MainActor
    private func launchVideoDetail(waitForDetailMarker: Bool = true, extraArguments: [String] = []) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-reset-state",
            "--start-tab", "home",
            "--ui-test-video-detail-network", "--ui-test-player-controls-persistent",
            "--start-bvid", "BV1xx411c7mD",
        ]
        app.launchArguments += extraArguments
        app.launch()
        XCTAssertTrue(
            element("video.detail.toolbar-picker", in: app).firstMatch.waitForExistence(timeout: 10)
        )
        if waitForDetailMarker {
            XCTAssertTrue(app.staticTexts["相关推荐"].waitForExistence(timeout: 10))
        }
        return app
    }
}
