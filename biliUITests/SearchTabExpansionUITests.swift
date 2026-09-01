import XCTest

final class SearchTabExpansionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSearchTabExpandsAndActivatesSearch() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-cc.bili.search.tabExpansionExperimentEnabled.v1", "YES"
        ]
        app.launch()

        let searchTab = app.tabBars.buttons["搜索"]
        let mineTab = app.tabBars.buttons["我的"]
        XCTAssertTrue(searchTab.waitForExistence(timeout: 10))
        XCTAssertTrue(mineTab.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(searchTab.frame.minX, mineTab.frame.maxX)
        searchTab.tap()

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let scope = app.buttons["综合"]
        let sort = app.staticTexts["综合排序"]
        XCTAssertTrue(scope.waitForExistence(timeout: 5))
        XCTAssertTrue(sort.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(searchField.frame.minY, app.frame.midY)
        XCTAssertLessThan(scope.frame.maxY, searchField.frame.minY)
        XCTAssertLessThan(sort.frame.maxY, searchField.frame.minY)
    }
}
