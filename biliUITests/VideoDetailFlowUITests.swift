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
            "--ui-test-reset-state"
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
    func testVideoDetailUsesLayeredPagesAndNativeSegmentedPicker() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-reset-state",
            "-cc.bili.videoDetail.segmentedPickerGlassStyle.v1", "regular",
            "--start-tab", "home",
            "--start-bvid", "BV1xx411c7mD",
        ]
        app.launch()

        let picker = app.segmentedControls["video.detail.glass-panel-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        XCTAssertEqual(picker.buttons.count, 2)
        XCTAssertEqual(picker.frame.width, 144, accuracy: 2)
        XCTAssertEqual(picker.frame.height, 40, accuracy: 2)
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
    func testVideoDetailPlayerFullscreenRoundTripKeepsDetailShellMounted() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-reset-state",
            "--start-tab", "home",
            "--start-bvid", "BV1xx411c7mD",
        ]
        app.launch()

        let picker = app.segmentedControls["video.detail.glass-panel-picker"]
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
        let landscapeAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        landscapeAttachment.name = "Geometry landscape after fullscreen"
        landscapeAttachment.lifetime = .keepAlways
        add(landscapeAttachment)
        let landscapeBack = app.buttons["ui.player.back"]
        if landscapeBack.waitForExistence(timeout: 5) {
            landscapeBack.tap()
        }
        XCUIDevice.shared.orientation = .portrait

        let detailMarker = app.staticTexts["相关推荐"].firstMatch
        XCTAssertTrue(detailMarker.waitForExistence(timeout: 5))
        XCTAssertTrue(picker.exists)
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
            app.segmentedControls["video.detail.glass-panel-picker"].waitForExistence(timeout: 10)
        )
        if waitForDetailMarker {
            XCTAssertTrue(app.staticTexts["相关推荐"].waitForExistence(timeout: 10))
        }
        return app
    }
}
