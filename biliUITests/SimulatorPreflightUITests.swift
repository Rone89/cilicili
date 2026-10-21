import XCTest

final class SimulatorPreflightUITests: XCTestCase {
    @MainActor
    func testFixtureLaunches() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "commentAction"]
        app.launch()
        XCTAssertTrue(app.buttons["ui.commentAction.open"].waitForExistence(timeout: 15))
    }
}
