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
        XCTAssertEqual(app.frame.maxY - picker.frame.maxY, 32, accuracy: 3)
        let detailButton = picker.buttons.element(boundBy: 0)
        let commentsButton = picker.buttons.element(boundBy: 1)

        XCTAssertFalse(app.tabBars.buttons["首页"].isHittable)
        XCTAssertFalse(app.tabBars.buttons["详情"].isHittable)
        XCTAssertFalse(app.tabBars.buttons["评论"].isHittable)

        let detailMarker = app.staticTexts["相关推荐"].firstMatch
        XCTAssertTrue(detailMarker.waitForExistence(timeout: 10))
        let initialDetailMarkerY = detailMarker.frame.minY
        app.swipeUp()
        let scrolledDetailMarkerY = detailMarker.frame.minY
        XCTAssertLessThan(scrolledDetailMarkerY, initialDetailMarkerY)

        commentsButton.tap()
        XCTAssertTrue(app.scrollViews.staticTexts["评论"].firstMatch.waitForExistence(timeout: 5))
        detailButton.tap()
        XCTAssertTrue(detailMarker.waitForExistence(timeout: 5))
        XCTAssertEqual(detailMarker.frame.minY, scrolledDetailMarkerY, accuracy: 8)

        app.swipeRight()
        let homeTab = app.tabBars.buttons["首页"]
        XCTAssertTrue(homeTab.waitForExistence(timeout: 5))
        XCTAssertTrue(homeTab.isHittable)
        XCTAssertFalse(picker.exists)
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}
