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
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}
