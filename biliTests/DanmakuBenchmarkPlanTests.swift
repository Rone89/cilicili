#if DEBUG
import XCTest
@testable import bili

final class DanmakuBenchmarkPlanTests: XCTestCase {
    func testEachDensityUsesIdenticalABBAInputs() {
        let plan = DanmakuBenchmarkPlan()
        XCTAssertEqual(plan.steps.count, 12)
        for (offset, density) in [50, 100, 300].enumerated() {
            let steps = Array(plan.steps[(offset * 4)..<(offset * 4 + 4)])
            XCTAssertEqual(steps.map(\.density), [density, density, density, density])
            XCTAssertEqual(steps.map(\.metal), [false, true, true, false])
        }
        XCTAssertEqual(plan.totalSeconds, 1116)
        XCTAssertEqual(DanmakuBenchmarkPlan(sampleSeconds: 15).totalSeconds, 216)
    }

    func testReportsIdentifySuiteStepAndIncompleteSamples() {
        let plan = DanmakuBenchmarkPlan()
        let id = UUID()
        let completed = plan.reportHeader(suiteID: id, index: 1, status: "completed")
        XCTAssertTrue(completed.contains(id.uuidString))
        XCTAssertTrue(completed.contains("step: 2/12; renderer: Metal; density: 50"))
        XCTAssertTrue(completed.contains("requested callback FPS: 60; playback rate: 1.0"))
        XCTAssertTrue(completed.contains("status: completed"))
        let partial = plan.reportHeader(suiteID: id, index: 0, status: "interrupted:appInactive")
        XCTAssertTrue(partial.contains("status: interrupted:appInactive"))
        XCTAssertFalse(partial.contains("status: completed"))
    }
}
#endif
