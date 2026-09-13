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

        app.buttons["ui.videoDetail.danmakuSettings"].tap()
        let picker = element("ui.videoDetail.sheet.danmakuSettings.displayArea", in: app)
        XCTAssertTrue(picker.waitForExistence(timeout: 2))
        let full = picker.buttons["全屏"]
        XCTAssertTrue(full.waitForExistence(timeout: 2))
        full.tap()
        app.buttons["ui.videoDetail.sheet.danmakuSettings.done"].tap()

        let persisted = element("ui.videoDetail.danmakuSettings.persistedValue", in: app)
        XCTAssertTrue(persisted.waitForExistence(timeout: 2))
        XCTAssertEqual(persisted.label, "full")

        app.terminate()
        app.launchArguments = ["--ui-test-fixture", "danmaku"]
        app.launch()
        let restored = element("ui.videoDetail.danmakuSettings.persistedValue", in: app)
        XCTAssertTrue(restored.waitForExistence(timeout: 5))
        XCTAssertEqual(restored.label, "full")
    }

    @MainActor
    func testVideoDetailUsesLayeredPagesAndToolbarPicker() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-reset-state",
            "-cc.bili.videoDetail.segmentedPickerGlassStyle.v1", "regular",
            "--start-tab", "home",
            "--start-bvid", "BV1xx411c7mD",
        ]
        app.launch()

        let picker = element("video.detail.toolbar-picker", in: app).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        XCTAssertEqual(picker.buttons.count, 2)
        XCTAssertEqual(picker.frame.width, 144, accuracy: 2)
        XCTAssertEqual(picker.frame.height, 38, accuracy: 2)
        let appFrame = app.windows.firstMatch.frame
        let pickerFrame = picker.frame
        XCTAssertGreaterThanOrEqual(pickerFrame.minX, appFrame.minX)
        XCTAssertGreaterThanOrEqual(pickerFrame.minY, appFrame.minY)
        XCTAssertLessThanOrEqual(pickerFrame.maxX, appFrame.maxX)
        XCTAssertLessThanOrEqual(pickerFrame.maxY, appFrame.maxY)
        XCTAssertGreaterThan(appFrame.maxY - pickerFrame.maxY, 0)
        XCTAssertTrue(picker.isHittable)
        let detailButton = picker.buttons.element(boundBy: 0)
        let commentsButton = picker.buttons.element(boundBy: 1)

        let detailMarker = app.staticTexts["相关推荐"].firstMatch
        XCTAssertTrue(detailMarker.waitForExistence(timeout: 10))
        let summary = app.descendants(matching: .any)["video.detail.summary"].firstMatch
        XCTAssertTrue(summary.exists)
        XCTAssertGreaterThanOrEqual(picker.frame.minY, summary.frame.maxY - 1)
        XCTAssertGreaterThan(picker.frame.minY, appFrame.midY)
        let initialDetailMarkerY = detailMarker.frame.minY
        app.swipeUp()
        let scrolledDetailMarkerY = detailMarker.frame.minY
        XCTAssertLessThan(scrolledDetailMarkerY, initialDetailMarkerY)
        XCTAssertTrue(picker.isHittable)
        let scrolledAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        scrolledAttachment.name = "Portrait floating bottom toolbar after scrolling"
        scrolledAttachment.lifetime = .keepAlways
        add(scrolledAttachment)
        XCTAssertEqual(picker.frame.minY, pickerFrame.minY, accuracy: 2)

        commentsButton.tap()
        XCTAssertTrue(app.scrollViews.staticTexts["评论"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["video.detail.summary"].firstMatch.exists)
        detailButton.tap()
        XCTAssertTrue(detailMarker.waitForExistence(timeout: 5))
        XCTAssertEqual(detailMarker.frame.minY, scrolledDetailMarkerY, accuracy: 8)

        app.swipeRight()
        let homeTab = app.buttons["首页"].firstMatch
        XCTAssertTrue(homeTab.waitForExistence(timeout: 5))
        XCTAssertTrue(homeTab.isHittable)
        XCTAssertFalse(picker.exists)
    }

    @MainActor
    func testVideoDetailToolbarCommentComposerIsAvailableWithoutExperimentFlag() {
        let app = launchVideoDetail(waitForDetailMarker: false)
        let picker = element("video.detail.toolbar-picker", in: app).firstMatch
        let commentsButton = picker.buttons["评论"]
        XCTAssertTrue(commentsButton.waitForExistence(timeout: 5))
        commentsButton.tap()

        let composeButton = app.buttons["video.detail.toolbar-comment-compose"]
        XCTAssertTrue(composeButton.waitForExistence(timeout: 5))
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

        let settledCommentHeaderFrame = commentHeader.frame
        let continuationStart = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        let remainingCollapse = playerFrame.frame.height - 54
        continuationStart.press(
            forDuration: 0.1,
            thenDragTo: continuationStart.withOffset(CGVector(dx: 0, dy: -(remainingCollapse + 30))),
            withVelocity: .slow,
            thenHoldForDuration: 0.2
        )
        let minimumPlayer = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                playerFrame.frame.height <= 55
            },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [minimumPlayer], timeout: 3), .completed)
        XCTAssertLessThan(
            commentHeader.frame.minY,
            settledCommentHeaderFrame.minY - 4,
            "comment content should start relative scrolling only after the player reaches minimum height"
        )
        let minimumAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        minimumAttachment.name = "Comment section scrolls after player minimum"
        minimumAttachment.lifetime = .keepAlways
        add(minimumAttachment)
        XCTAssertEqual(playerFrame.frame.height, 54, accuracy: 1)
        XCTAssertTrue(commentHeader.exists)
        XCTAssertLessThan(
            commentHeader.frame.minY,
            scrollView.frame.maxY,
            "comment header should remain in the scroll viewport after the player reaches minimum height"
        )
        XCTAssertGreaterThan(
            commentHeader.frame.maxY,
            scrollView.frame.minY,
            "comment header should not be scrolled completely above the viewport"
        )
    }

    @MainActor
    func testVideoDetailPlayerFullscreenRoundTripKeepsDetailShellMounted() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-reset-state",
            "--start-tab", "home",
            "--start-bvid", "BV1xx411c7mD",
        ]
        app.launch()

        let picker = element("video.detail.toolbar-picker", in: app).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 10))

        let fullscreen = app.buttons["ui.player.fullscreen.toggle"]
        XCTAssertTrue(fullscreen.waitForExistence(timeout: 5))
        if !fullscreen.isHittable {
            let surface = app.buttons["ui.player.surface"]
            XCTAssertTrue(surface.waitForExistence(timeout: 5))
            surface.tap()
        }
        XCTAssertTrue(fullscreen.isHittable)
        let portraitAttachment = XCTAttachment(screenshot: app.screenshot())
        portraitAttachment.name = "Geometry portrait before fullscreen"
        portraitAttachment.lifetime = .keepAlways
        add(portraitAttachment)
        fullscreen.tap()

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
        let landscapeBack = app.buttons["ui.player.back"]
        if !landscapeBack.waitForExistence(timeout: 2) || !landscapeBack.isHittable {
            let surface = app.buttons["ui.player.surface"]
            XCTAssertTrue(surface.waitForExistence(timeout: 5))
            surface.tap()
        }
        XCTAssertTrue(landscapeBack.waitForExistence(timeout: 5))
        XCTAssertTrue(landscapeBack.isHittable)
        landscapeBack.tap()
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
        let more = app.buttons["ui.player.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()

        let quality = app.descendants(matching: .any)["ui.player.quality"].firstMatch
        XCTAssertTrue(quality.waitForExistence(timeout: 5))
        quality.tap()

        let qualityTitle = app.navigationBars["清晰度"]
        XCTAssertTrue(qualityTitle.waitForExistence(timeout: 5))
        let choices = app.buttons
        XCTAssertGreaterThan(choices.count, 0)
        choices.element(boundBy: 0).tap()

        XCTAssertTrue(app.buttons["ui.player.fullscreen.toggle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["相关推荐"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testVideoDetailDanmakuInteractionKeepsPlayerSurfaceMounted() {
        let app = launchVideoDetail(waitForDetailMarker: false)
        let more = app.buttons["ui.player.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()
        let settings = app.buttons["弹幕设置"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()

        XCTAssertTrue(app.staticTexts["相关推荐"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["ui.player.fullscreen.toggle"].exists)
    }

    @MainActor
    func testVideoDetailRapidRotationPublishesStableIdentityDiagnostics() {
        let app = launchVideoDetail(waitForDetailMarker: false)
        let fullscreen = app.buttons["ui.player.fullscreen.toggle"]
        XCTAssertTrue(fullscreen.waitForExistence(timeout: 5))

        fullscreen.tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCUIDevice.shared.orientation = .portrait
        XCUIDevice.shared.orientation = .landscapeRight
        XCUIDevice.shared.orientation = .portrait

        let diagnostics = app.descendants(matching: .any)["ui.videoDetail.rotationDiagnostics"].firstMatch
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 15))
        let value = diagnostics.value as? String ?? ""
        print("rotationDiagnostics=\(value)")
        XCTAssertTrue(value.contains("playerViewModelIdentity"))
        XCTAssertTrue(value.contains("avPlayerIdentity"))
        XCTAssertTrue(value.contains("avPlayerItemIdentity"))
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
        let fullscreen = app.buttons["ui.player.fullscreen.toggle"]
        XCTAssertTrue(fullscreen.waitForExistence(timeout: 5))

        fullscreen.tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCUIDevice.shared.orientation = .portrait

        XCTAssertTrue(app.staticTexts["相关推荐"].waitForExistence(timeout: 15))
        if !app.buttons["ui.player.fullscreen.toggle"].exists {
            app.buttons["ui.player.surface"].tap()
        }
        XCTAssertTrue(app.buttons["ui.player.fullscreen.toggle"].waitForExistence(timeout: 5))
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

        let fullscreen = app.buttons["ui.player.fullscreen.toggle"]
        if fullscreen.exists {
            XCTAssertTrue(fullscreen.isHittable)
        }
    }

    @MainActor
    func testVideoDetailExitDuringRotationReturnsToHomeWithoutRebuildingPlayer() {
        let app = launchVideoDetail(waitForDetailMarker: false)
        let fullscreen = app.buttons["ui.player.fullscreen.toggle"]
        XCTAssertTrue(fullscreen.waitForExistence(timeout: 5))

        fullscreen.tap()
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
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
        let homeTab = app.buttons["首页"].firstMatch
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
    private func verifyAutoplayCommentOrigin(autoplayEnabled: Bool = true) {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-reset-state",
            "-cc.bili.videoDetail.autoplayEnabled.v1", autoplayEnabled ? "YES" : "NO",
            "--start-tab", "home",
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

        let surface = app.buttons["ui.player.surface"].firstMatch
        XCTAssertTrue(surface.waitForExistence(timeout: 5))
        if !autoplayEnabled {
            let initialPlayButton = app.buttons["播放"].firstMatch
            if initialPlayButton.isHittable {
                initialPlayButton.tap()
            } else {
                surface.tap()
            }
            XCTAssertEqual(commentHeader.frame.minY, playingHeaderFrame.minY, accuracy: 1)
        } else {
            surface.tap()
        }
        let pauseButton = app.buttons["暂停"].firstMatch
        if !autoplayEnabled && !pauseButton.isHittable {
            surface.tap()
        }
        XCTAssertTrue(pauseButton.waitForExistence(timeout: 10))
        pauseButton.tap()

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

        playButton.tap()
        XCTAssertTrue(pauseButton.waitForExistence(timeout: 5))
        XCTAssertEqual(commentHeader.frame.minY, playingHeaderFrame.minY, accuracy: 1)
        XCTAssertEqual(playerFrame.frame.height, playingPlayerFrame.height, accuracy: 1)
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
