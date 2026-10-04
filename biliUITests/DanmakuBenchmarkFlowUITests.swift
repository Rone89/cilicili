import XCTest

final class DanmakuBenchmarkFlowUITests: XCTestCase {
    @MainActor
    func testAutomaticABBACompletesAndSavesFourIndependentReports() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "danmakuBenchmark", "--danmaku-auto-test-short"]
        app.launch()
        let automatic = app.buttons["danmaku.benchmark.automatic"]
        XCTAssertTrue(automatic.waitForExistence(timeout: 10))
        automatic.tap()
        let progress = app.staticTexts["danmaku.benchmark.progress"]
        let finished = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "自动测试完成"), object: progress)
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 25), .completed, progress.label)
        let copy = app.buttons["danmaku.benchmark.copy"]
        XCTAssertTrue(copy.isEnabled)
        XCTAssertTrue(copy.label.contains("4份"), copy.label)
        XCTAssertTrue(app.buttons["分享自动测试报告"].exists)
        XCTAssertTrue(app.switches["danmaku.benchmark.metal"].isEnabled)
        copy.tap()
        XCTAssertEqual(copy.label, "已复制")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["分享自动测试报告"].waitForExistence(timeout: 10))
        app.terminate()
    }

    @MainActor
    func testStoppingAutomaticCaptureUnlocksControls() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "danmakuBenchmark"]
        app.launch()
        let automatic = app.buttons["danmaku.benchmark.automatic"]
        XCTAssertTrue(automatic.waitForExistence(timeout: 10))
        automatic.tap()
        let metal = app.switches["danmaku.benchmark.metal"]
        XCTAssertFalse(metal.isEnabled)
        let samples = app.staticTexts["danmaku.benchmark.samples"]
        let recording = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label MATCHES %@", ".*Kit=[1-9][0-9]* Metal=0.*"), object: samples)
        XCTAssertEqual(XCTWaiter.wait(for: [recording], timeout: 10), .completed)
        automatic.tap()
        XCTAssertTrue(metal.isEnabled)
        XCTAssertTrue(app.staticTexts["danmaku.benchmark.progress"].label.contains("已停止"))
        XCTAssertTrue(app.buttons["danmaku.benchmark.copy"].label.contains("1份"))
        // A stopped run must not later switch renderer or restart the capture.
        XCTAssertEqual(metal.value as? String, "0")
        XCTAssertEqual(app.buttons["danmaku.benchmark.capture"].label, "开始独立采集")
        app.terminate()
    }

    @MainActor
    func testBackgroundingStopsAutomaticRunAndPreservesReport() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "danmakuBenchmark"]
        app.launch()
        let automatic = app.buttons["danmaku.benchmark.automatic"]
        XCTAssertTrue(automatic.waitForExistence(timeout: 10))
        automatic.tap()
        let samples = app.staticTexts["danmaku.benchmark.samples"]
        let recording = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label MATCHES %@", ".*Kit=[1-9][0-9]* Metal=0.*"), object: samples)
        XCTAssertEqual(XCTWaiter.wait(for: [recording], timeout: 10), .completed)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.staticTexts["danmaku.benchmark.progress"].label.contains("已停止"))
        XCTAssertTrue(app.switches["danmaku.benchmark.metal"].isEnabled)
        XCTAssertTrue(app.buttons["分享自动测试报告"].exists)
        XCTAssertEqual(app.buttons["danmaku.benchmark.capture"].label, "开始独立采集")
        app.terminate()
    }

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
