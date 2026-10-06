import XCTest

@MainActor
final class VideoDetailSponsoredBadgeUITests: XCTestCase {
    func testVisibilityMatrixAndMissingAttribute() {
        let app = launchFixture()
        let badge = app.staticTexts["video.detail.sponsoredBadge"]
        let title = app.staticTexts["video.detail.title"]
        let originalFrame = title.frame
        XCTAssertFalse(badge.exists) // OFF + ordinary
        toggle("sponsored", in: app)
        XCTAssertFalse(badge.exists) // OFF + sponsored
        XCTAssertEqual(title.frame, originalFrame)
        toggle("enabled", in: app)
        XCTAssertTrue(badge.waitForExistence(timeout: 2)) // ON + sponsored
        XCTAssertEqual(badge.label, "恰饭")
        toggle("sponsored", in: app)
        XCTAssertFalse(badge.exists) // ON + ordinary, no reserved space
        XCTAssertEqual(title.frame, originalFrame)
        toggle("sponsored", in: app)
        toggle("attribute", in: app)
        XCTAssertFalse(badge.exists)
        XCTAssertEqual(title.label, "这是一个视频标题")
        XCTAssertEqual(title.frame, originalFrame)
    }

    func testLongTitleAndCapsuleLayoutInLightAndDarkModes() {
        let app = launchFixture()
        toggle("enabled", in: app)
        toggle("sponsored", in: app)
        let badge = app.staticTexts["video.detail.sponsoredBadge"]
        let title = app.staticTexts["video.detail.title"]
        XCTAssertTrue(badge.waitForExistence(timeout: 2))
        let lineHeight = title.frame.height
        toggle("longTitle", in: app)
        toggle("expanded", in: app)
        for mode in ["Light", "Dark"] {
            XCTAssertGreaterThan(title.frame.height, lineHeight * 2)
            XCTAssertGreaterThan(title.frame.minX, badge.frame.maxX)
            XCTAssertLessThanOrEqual(badge.frame.height, lineHeight + 2)
            XCTAssertLessThan(abs(title.frame.minY - badge.frame.minY), lineHeight * 0.4)
            XCTAssertTrue(title.label.hasSuffix("标题的最后一句话。"))
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Sponsored long title \(mode)"
            attachment.lifetime = .keepAlways
            add(attachment)
            if mode == "Light" { toggle("dark", in: app) }
        }
    }

    private func launchFixture() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "videoSponsoredBadge"]
        app.launch()
        XCTAssertTrue(app.staticTexts["video.detail.title"].waitForExistence(timeout: 5))
        addTeardownBlock { app.terminate() }
        return app
    }

    private func toggle(_ name: String, in app: XCUIApplication) {
        let element = app.switches["fixture.badge.\(name)"]
        let previous = element.value as? String
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertNotEqual(element.value as? String, previous)
    }
}
