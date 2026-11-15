import XCTest

final class MineSearchMorphProbeUITests: XCTestCase {
    @MainActor
    func testProbeMorph() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "mineTopBar", "--ui-test-enable-animations"]
        app.launch()
        let button = app.buttons["mine.search.button"]
        XCTAssertTrue(button.waitForExistence(timeout: 20))

        let lock = NSLock()
        var frames: [(Int, Data)] = []
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            for index in 0..<20 {
                let data = XCUIScreen.main.screenshot().pngRepresentation
                lock.lock()
                frames.append((index, data))
                lock.unlock()
                usleep(35_000)
            }
            done.signal()
        }
        button.tap()
        done.wait()
        for frame in frames {
            let attachment = XCTAttachment(data: frame.1, uniformTypeIdentifier: "public.png")
            attachment.name = String(format: "morph-%02d", frame.0)
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
