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
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}
