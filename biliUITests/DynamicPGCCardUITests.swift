import XCTest

@MainActor
final class DynamicPGCCardUITests: XCTestCase {
    func testDefaultPGCCardsRouteToExactEpisodeForFeedAndForward() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "dynamicPGC"]
        app.launch()
        defer { app.terminate() }
        let first = app.buttons["dynamic.pgc.card.101"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
        XCTAssertEqual(app.staticTexts["pgc.fixture.episode"].label, "101")
        let forwarded = app.buttons["dynamic.pgc.card.102"]
        for _ in 0..<4 where !forwarded.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(forwarded.isHittable)
        forwarded.tap()
        let selectedEpisode = app.staticTexts["pgc.fixture.episode"]
        for _ in 0..<4 where !selectedEpisode.isHittable { app.scrollViews.firstMatch.swipeDown() }
        XCTAssertEqual(selectedEpisode.label, "102")
    }
}
