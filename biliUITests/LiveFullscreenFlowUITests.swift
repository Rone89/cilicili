import XCTest

final class LiveFullscreenFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFullscreenEntersAndExits() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "fullscreen"]
        app.launch()
        let ready = element("ui.live.ready", in: app)
        XCTAssertTrue(ready.waitForExistence(timeout: 5))

        let enter = app.buttons["ui.live.player.fullscreen"]
        XCTAssertTrue(enter.waitForExistence(timeout: 2))
        enter.tap()

        let fullscreen = element("ui.live.fullscreenSurface", in: app)
        XCTAssertTrue(fullscreen.waitForExistence(timeout: 2))

        let exit = app.buttons["ui.live.player.exitFullscreen"]
        XCTAssertTrue(exit.waitForExistence(timeout: 2))
        exit.tap()
        XCTAssertTrue(ready.waitForExistence(timeout: 2))
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}
