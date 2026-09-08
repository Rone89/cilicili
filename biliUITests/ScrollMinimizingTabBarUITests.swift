import XCTest

@MainActor
final class ScrollMinimizingTabBarUITests: XCTestCase {
    private let experimentKey = "cc.bili.experimental.scrollMinimizingTabBar.v1"

    func testHomeFeedScrollMinimizesReplacementTabBar() {
        let app = XCUIApplication()
        app.launchArguments += ["-\(experimentKey)", "YES"]
        app.launch()

        let tabButtons = app.buttons.matching(identifier: "root.scrollMinimizingTabBar")
        XCTAssertTrue(tabButtons.firstMatch.waitForExistence(timeout: 8))

        let expandedWidth = tabBarWidth(tabButtons)
        addScreenshot(named: "Expanded scroll-minimizing tab bar", app: app)

        app.swipeUp()

        let minimized = expectation(description: "tab bar minimizes after a downward scroll")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            minimized.fulfill()
        }
        wait(for: [minimized], timeout: 2)

        XCTAssertLessThan(tabBarWidth(tabButtons), expandedWidth)
        addScreenshot(named: "Minimized scroll-minimizing tab bar", app: app)
    }

    private func tabBarWidth(_ buttons: XCUIElementQuery) -> CGFloat {
        let frames = buttons.allElementsBoundByIndex.map(\.frame)
        guard let first = frames.first else { return 0 }
        let minX = frames.map(\.minX).min() ?? first.minX
        let maxX = frames.map(\.maxX).max() ?? first.maxX
        return maxX - minX
    }

    private func addScreenshot(named: String, app: XCUIApplication) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = named
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
