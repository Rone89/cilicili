import XCTest

final class DanmakuBenchmarkFlowUITests: XCTestCase {
    @MainActor
    func testIndependentKitAndMetalCapturesLockConfigurationAndSaveSeparateReports() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "danmakuBenchmark"]
        app.launch()
        let capture = app.buttons["danmaku.benchmark.capture"]
        let copy = app.buttons["danmaku.benchmark.copy"]
        let metal = app.switches["danmaku.benchmark.metal"]
        let samples = app.staticTexts["danmaku.benchmark.samples"]
        XCTAssertTrue(capture.waitForExistence(timeout: 10))
        XCTAssertFalse(copy.isEnabled)
        capture.tap()
        XCTAssertFalse(metal.isEnabled)
        let kitRecorded = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label MATCHES %@", ".*Kit=[1-9][0-9]* Metal=0.*"), object: samples)
        XCTAssertEqual(XCTWaiter.wait(for: [kitRecorded], timeout: 10), .completed)
        capture.tap()
        XCTAssertTrue(metal.isEnabled)
        XCTAssertTrue(copy.isEnabled)
        XCTAssertTrue(copy.label.contains("1份"))
        // SwiftUI exposes the label and switch as one wide accessibility element.
        metal.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let switched = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: metal)
        XCTAssertEqual(XCTWaiter.wait(for: [switched], timeout: 5), .completed)
        capture.tap()
        XCTAssertFalse(metal.isEnabled)
        let metalRecorded = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label MATCHES %@", ".*Kit=0 Metal=[1-9][0-9]*.*"), object: samples)
        XCTAssertEqual(XCTWaiter.wait(for: [metalRecorded], timeout: 10), .completed, samples.label)
        capture.tap()
        XCTAssertTrue(copy.label.contains("2份"))
        copy.tap()
        XCTAssertEqual(copy.label, "已复制")
        app.terminate()
    }
}
