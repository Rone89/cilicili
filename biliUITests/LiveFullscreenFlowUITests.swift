import XCTest

final class LiveFullscreenFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFullscreenEntersAndExits() {
        let app = launchPlayerFixture()
        let ready = element("ui.player.ready", in: app)
        XCTAssertTrue(ready.waitForExistence(timeout: 5))
        XCTAssertEqual(element("ui.player.lifecycleState", in: app).label, "active")
        let surface = element("ui.player.surface", in: app)
        XCTAssertTrue(surface.waitForExistence(timeout: 2))

        let enter = app.buttons["ui.player.fullscreen.toggle"]
        XCTAssertTrue(enter.waitForExistence(timeout: 2))
        let isHittable = NSPredicate(format: "hittable == true")
        expectation(for: isHittable, evaluatedWith: enter)
        waitForExpectations(timeout: 2)
        enter.tap()

        let exit = app.buttons["ui.player.fullscreen.toggle"]
        let showsExitFullscreen = NSPredicate(format: "label == '退出全屏'")
        expectation(for: showsExitFullscreen, evaluatedWith: exit)
        waitForExpectations(timeout: 2)
        exit.tap()
        let showsEnterFullscreen = NSPredicate(format: "label == '全屏'")
        expectation(for: showsEnterFullscreen, evaluatedWith: enter)
        waitForExpectations(timeout: 2)
    }

    @MainActor
    func testPlaybackFailureRetriesSuccessfully() {
        let app = launchPlayerFixture()
        XCTAssertTrue(element("ui.player.ready", in: app).waitForExistence(timeout: 5))

        let fail = app.buttons["ui.player.simulateFailure"]
        XCTAssertTrue(fail.waitForExistence(timeout: 2))
        fail.tap()

        let error = element("ui.player.error", in: app)
        XCTAssertTrue(error.waitForExistence(timeout: 2))
        XCTAssertTrue(error.label.contains("UI Test Playback Failed"))

        let retry = app.buttons["ui.player.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 2))
        retry.tap()
        XCTAssertFalse(error.waitForExistence(timeout: 2))
        XCTAssertTrue(element("ui.player.ready", in: app).exists)
    }

    @MainActor
    func testClosingPlayerSuspendsPlaybackForNavigation() {
        let app = launchPlayerFixture()
        XCTAssertTrue(element("ui.player.ready", in: app).waitForExistence(timeout: 5))

        let close = app.buttons["ui.player.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 2))
        close.tap()

        XCTAssertTrue(element("ui.player.navigationReturned", in: app).waitForExistence(timeout: 2))
        let state = element("ui.player.navigationState", in: app)
        XCTAssertTrue(state.waitForExistence(timeout: 2))
        let suspended = NSPredicate(format: "label == 'suspended'")
        expectation(for: suspended, evaluatedWith: state)
        waitForExpectations(timeout: 2)
    }

    @MainActor
    private func launchPlayerFixture() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "fullscreen"]
        app.launch()
        return app
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}
