import XCTest

final class VideoDetailFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
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
        let commentHeader = app.scrollViews.staticTexts["评论"].firstMatch
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
        let commentHeader = app.scrollViews.staticTexts["评论"].firstMatch
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
        let scrollView = app.scrollViews.allElementsBoundByIndex.first { scrollView in
            scrollView.isHittable && scrollView.frame.contains(commentHeader.frame)
        }
        XCTAssertNotNil(scrollView)
        guard let scrollView else { return }

        let dragStart = commentHeader.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let dragEnd = dragStart.withOffset(CGVector(dx: 0, dy: -32))
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

        // Stop short of the minimum first. A gesture that crosses the boundary
        // can legitimately continue scrolling the comments.
        for _ in 0..<24 {
            let remainingCollapse = playerFrame.frame.height - 54
            if remainingCollapse <= 16 { break }
            let start = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            let dragEnd = start.withOffset(
                CGVector(dx: 0, dy: -min(24, remainingCollapse))
            )
            start.press(
                forDuration: 0.8,
                thenDragTo: dragEnd,
                withVelocity: .slow,
                thenHoldForDuration: 1.0
            )
        }
        let headerBeforeMinimum = commentHeader.frame
        XCTAssertGreaterThan(
            playerFrame.frame.height,
            54,
            "player should remain above its minimum before the final collapse drag"
        )
        XCTAssertGreaterThan(
            headerBeforeMinimum.maxY,
            scrollView.frame.minY,
            "comment header should remain visible until the player reaches its minimum height"
        )
        let finalCollapseStart = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        let finalCollapseEnd = finalCollapseStart.withOffset(CGVector(dx: 0, dy: -24))
        finalCollapseStart.press(
            forDuration: 0.8,
            thenDragTo: finalCollapseEnd,
            withVelocity: .slow,
            thenHoldForDuration: 0.2
        )
        for _ in 0..<48 {
            let remainingCollapse = playerFrame.frame.height - 54
            if remainingCollapse <= 1 { break }
            let dragDistance: CGFloat
            if remainingCollapse > 24 {
                dragDistance = 24
            } else if remainingCollapse > 8 {
                dragDistance = 8
            } else {
                dragDistance = max(remainingCollapse, 1)
            }
            let start = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            start.press(
                forDuration: 0.8,
                thenDragTo: start.withOffset(CGVector(dx: 0, dy: -dragDistance)),
                withVelocity: .slow,
                thenHoldForDuration: 1.0
            )
        }
        let minimumPlayer = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                playerFrame.frame.height <= 55
            },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [minimumPlayer], timeout: 3), .completed)
        let headerAtMinimum = commentHeader.frame
        let continuationStart = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        continuationStart.press(
            forDuration: 0.8,
            thenDragTo: continuationStart.withOffset(CGVector(dx: 0, dy: -20)),
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
        let landscapeAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        landscapeAttachment.name = "Geometry landscape after fullscreen"
        landscapeAttachment.lifetime = .keepAlways
        add(landscapeAttachment)
        XCTAssertFalse(app.buttons["ui.player.back"].exists)
        if !waitForVisiblePlayerControl(in: app, { fullscreenControl(in: app) }, timeout: 2) {
            let surface = app.buttons["ui.player.surface"]
            XCTAssertTrue(surface.waitForExistence(timeout: 5))
            surface.tap()
        }
        XCTAssertTrue(waitForVisiblePlayerControl(in: app, { fullscreenControl(in: app) }, timeout: 5))
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
        let detailMarker = app.staticTexts["相关推荐"].firstMatch
        XCTAssertTrue(detailMarker.waitForExistence(timeout: 5))
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
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

        backgroundPlayback.tap()
        XCTAssertEqual(backgroundPlayback.value as? String, "1")
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
        let commentHeader = app.scrollViews.staticTexts["评论"].firstMatch
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

    @MainActor
    private func launchVideoDetail(waitForDetailMarker: Bool = true) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-reset-state",
            "--start-tab", "home",
            "--ui-test-video-detail-network", "--ui-test-player-controls-persistent",
            "--start-bvid", "BV1xx411c7mD",
        ]
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
