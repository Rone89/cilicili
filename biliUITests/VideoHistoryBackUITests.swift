import XCTest

final class VideoHistoryBackUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testShortTapPopsToRoot() {
        let app = launch()
        app.buttons["history.fixture.open"].tap()
        back(in: app).tap()
        XCTAssertTrue(app.buttons["history.fixture.open"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testHistoryPopPreservesInstanceAndCommentSelection() {
        let app = launch()
        app.buttons["history.fixture.open"].tap()
        next(in: app)
        let instance = app.staticTexts["history.fixture.instance"].label
        app.buttons["评论"].firstMatch.tap()
        next(in: app)
        back(in: app).press(forDuration: 1)
        let previous = app.buttons["video.detail.history.depth.2"]
        XCTAssertTrue(previous.waitForExistence(timeout: 3))
        XCTAssertEqual(previous.label, "Video B")
        XCTAssertEqual(app.buttons["video.detail.history.depth.1"].label, "Video A")
        XCTAssertEqual(app.buttons["video.detail.history.depth.0"].label, "首页")
        XCTAssertFalse(app.buttons["Video C"].exists)
        previous.tap()
        XCTAssertTrue(app.buttons["history.fixture.next"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["history.fixture.instance"].label, instance)
        XCTAssertEqual(app.staticTexts["history.fixture.selection"].label, "comments")
        next(in: app)
        back(in: app).press(forDuration: 1)
        app.buttons["video.detail.history.depth.1"].tap()
        XCTAssertTrue(app.buttons["history.fixture.next"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["history.fixture.title"].label, "Video A")
        back(in: app).press(forDuration: 1)
        app.buttons["video.detail.history.depth.0"].tap()
        XCTAssertTrue(app.buttons["history.fixture.open"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testDuplicateTitlesPopByDepth() {
        let app = launch(extra: ["--history-duplicate"])
        app.buttons["history.fixture.open"].tap()
        let firstInstance = app.staticTexts["history.fixture.instance"].label
        next(in: app)
        let secondInstance = app.staticTexts["history.fixture.instance"].label
        XCTAssertNotEqual(firstInstance, secondInstance)
        next(in: app)
        back(in: app).press(forDuration: 1)
        XCTAssertEqual(app.buttons["video.detail.history.depth.2"].label, "同名视频")
        XCTAssertEqual(app.buttons["video.detail.history.depth.1"].label, "同名视频")
        app.buttons["video.detail.history.depth.2"].tap()
        XCTAssertTrue(app.buttons["history.fixture.next"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["history.fixture.instance"].label, secondInstance)
        next(in: app)
        back(in: app).press(forDuration: 1)
        app.buttons["video.detail.history.depth.1"].tap()
        XCTAssertTrue(app.buttons["history.fixture.next"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["history.fixture.instance"].label, firstInstance)
    }

    @MainActor
    func testMixedHistoryAndSystemEdgeSwipe() {
        let app = launch(extra: ["--history-mixed"])
        app.buttons["history.fixture.open"].tap()
        app.buttons["history.fixture.owner"].tap()
        app.buttons["history.fixture.video"].tap()
        next(in: app)
        back(in: app).press(forDuration: 1)
        XCTAssertEqual(app.buttons["video.detail.history.depth.3"].label, "Video A")
        XCTAssertEqual(app.buttons["video.detail.history.depth.2"].label, "某 UP 主空间")
        XCTAssertEqual(app.buttons["video.detail.history.depth.1"].label, "搜索结果")
        XCTAssertEqual(app.buttons["video.detail.history.depth.0"].label, "搜索")
        app.buttons["video.detail.history.depth.2"].tap()
        XCTAssertTrue(app.buttons["history.fixture.video"].waitForExistence(timeout: 3))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
        XCTAssertTrue(app.buttons["history.fixture.owner"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testFullLongTitleReachesSystemMenu() {
        let app = launch(extra: ["--history-long-title"])
        app.buttons["history.fixture.open"].tap()
        next(in: app)
        back(in: app).press(forDuration: 1)
        let item = app.buttons["video.detail.history.depth.1"]
        XCTAssertTrue(item.waitForExistence(timeout: 3))
        XCTAssertEqual(item.label, String(repeating: "这是一个非常非常长的视频标题完整内容", count: 8))
        item.tap()
        XCTAssertTrue(app.buttons["history.fixture.next"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func launch(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "historyBack", "--ui-test-enable-animations"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["history.fixture.open"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func back(in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons["video.detail.history-back"]
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        return button
    }

    @MainActor
    private func next(in app: XCUIApplication) {
        let button = app.buttons["history.fixture.next"]
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        button.tap()
    }
}
