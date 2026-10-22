import Foundation
import XCTest

final class SimulatorPreflightUITests: XCTestCase {
    @MainActor
    func testFixtureLaunches() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "commentAction"]
        app.launch()
        XCTAssertTrue(app.buttons["ui.commentAction.open"].waitForExistence(timeout: 15))
        if let token = ProcessInfo.processInfo.environment["CILICILI_PHOTO_IMPORT_TOKEN"] {
            // Keep Xcode's simulator alive until the host confirms addmedia.
            // A unique token prevents an earlier run's marker satisfying this wait.
            let marker = URL.documentsDirectory.appendingPathComponent(
                "cilicili-photo-fixture-\(token)"
            )
            let imported = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in
                    FileManager.default.fileExists(atPath: marker.path)
                },
                object: nil
            )
            let result = XCTWaiter.wait(for: [imported], timeout: 240)
            XCTAssertEqual(result, .completed)
            guard result == .completed else { return }
            print("PHOTO_IMPORT_CONFIRMED \(token)")
        }
    }
}
