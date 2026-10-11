import XCTest

@MainActor
final class DynamicPGCCardUITests: XCTestCase {
    func testExperimentSwitchAndExactEpisodeRouteForFeedAndForward() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "dynamicPGC"]
        app.launch()
        defer { app.terminate() }
        let toggle = app.switches["pgc.fixture.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["dynamic.pgc.card.101"].exists)
        toggle.tap()
        let first = app.buttons["dynamic.pgc.card.101"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
        XCTAssertEqual(app.staticTexts["pgc.fixture.episode"].label, "101")
        let forwarded = app.buttons["dynamic.pgc.card.102"]
        for _ in 0..<4 where !forwarded.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(forwarded.isHittable)
        forwarded.tap()
        for _ in 0..<4 where !toggle.isHittable { app.scrollViews.firstMatch.swipeDown() }
        XCTAssertEqual(app.staticTexts["pgc.fixture.episode"].label, "102")
        toggle.tap()
        XCTAssertFalse(app.buttons["dynamic.pgc.card.101"].exists)
        XCTAssertFalse(app.buttons["dynamic.pgc.card.102"].exists)
    }
}
