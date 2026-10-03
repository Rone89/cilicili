import XCTest
@testable import bili

@MainActor
final class MetalDanmakuFrameRatePolicyTests: XCTestCase {
    func testUsesDisplayMaximumWhenUnconstrained() {
        XCTAssertEqual(preferredFPS(displayMaximum: 120), 120)
        XCTAssertEqual(preferredFPS(displayMaximum: 60), 60)
    }

    func testFallsBackToSixtyWhenDisplayMaximumIsUnavailable() {
        XCTAssertEqual(preferredFPS(displayMaximum: 0), 60)
    }

    func testCapsUnsupportedDisplayMaximumAtOneHundredTwenty() {
        XCTAssertEqual(preferredFPS(displayMaximum: 144), 120)
    }

    func testUsesThirtyDuringLoadShedding() {
        XCTAssertEqual(preferredFPS(displayMaximum: 120, loadShedding: true), 30)
    }

    func testUsesThirtyInLowPowerMode() {
        XCTAssertEqual(preferredFPS(displayMaximum: 120, lowPowerMode: true), 30)
    }

    func testUsesThirtyWhenThermallyConstrained() {
        XCTAssertEqual(preferredFPS(displayMaximum: 120, thermallyConstrained: true), 30)
    }

    private func preferredFPS(
        displayMaximum: Int,
        loadShedding: Bool = false,
        lowPowerMode: Bool = false,
        thermallyConstrained: Bool = false
    ) -> Int {
        MetalDanmakuFrameRatePolicy.preferredFramesPerSecond(
            displayMaximum: displayMaximum,
            isLoadShedding: loadShedding,
            isLowPowerMode: lowPowerMode,
            isThermallyConstrained: thermallyConstrained
        )
    }
}
