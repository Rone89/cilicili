import XCTest
@testable import bili

final class UserSeekRevealDeadlineTests: XCTestCase {
    private func makeDeadline(
        targetTime: Double = 120,
        readySince: Double = 10,
        settleDelay: Double = 0.12,
        seekGeneration: Int = 1,
        surfaceGeneration: Int = 1
    ) -> UserSeekRevealDeadline {
        UserSeekRevealDeadline(
            targetTime: targetTime,
            readySince: readySince,
            settleDelay: settleDelay,
            seekGeneration: seekGeneration,
            surfaceGeneration: surfaceGeneration
        )!
    }

    func test120MillisecondWindowUsesFixedDeadline() {
        let plan = makeDeadline()

        XCTAssertEqual(plan.deadline, 10.12, accuracy: 0.000000001)
        XCTAssertNotNil(plan.remainingDelay(at: plan.deadline - 0.000001))
        XCTAssertNil(plan.remainingDelay(at: plan.deadline))
    }

    func testRemainingDelayIsDeterministicBeforeDeadline() {
        let plan = makeDeadline()
        let first = plan.remainingDelay(at: 10.05)
        let second = plan.remainingDelay(at: 10.05)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first!, 0.07, accuracy: 0.000000001)
        XCTAssertNil(plan.remainingDelay(at: .nan))
        XCTAssertNil(plan.remainingDelay(at: .infinity))
        XCTAssertNil(plan.remainingDelay(at: -.infinity))
    }

    func testRemainingDelayRejectsSubtractionOverflow() {
        let plan = makeDeadline(readySince: .greatestFiniteMagnitude, settleDelay: 0)
        XCTAssertNil(plan.remainingDelay(at: -.greatestFiniteMagnitude))
    }

    func testExpiredDeadlineDoesNotRepeat() {
        let plan = makeDeadline()

        XCTAssertNil(plan.remainingDelay(at: 10.13))
        XCTAssertNil(plan.remainingDelay(at: 10.13))
    }

    func testNewSeekGenerationInvalidatesEvenWhenTargetIsSame() {
        let plan = makeDeadline()

        XCTAssertTrue(plan.matches(targetTime: 120, readySince: 10,
            seekGeneration: 1, surfaceGeneration: 1))
        XCTAssertFalse(plan.matches(targetTime: 120, readySince: 10,
            seekGeneration: 2, surfaceGeneration: 1))
    }

    func testSurfaceGenerationChangeInvalidatesPlan() {
        let plan = makeDeadline()

        XCTAssertFalse(plan.matches(targetTime: 120, readySince: 10,
            seekGeneration: 1, surfaceGeneration: 2))
    }

    func testReadySinceResetOrChangeInvalidatesPlan() {
        let plan = makeDeadline()

        XCTAssertFalse(plan.matches(targetTime: 120, readySince: nil,
            seekGeneration: 1, surfaceGeneration: 1))
        XCTAssertFalse(plan.matches(targetTime: 120, readySince: 10.01,
            seekGeneration: 1, surfaceGeneration: 1))
    }

    func testTargetChangeInvalidatesPlan() {
        let plan = makeDeadline()

        XCTAssertFalse(plan.matches(targetTime: nil, readySince: 10,
            seekGeneration: 1, surfaceGeneration: 1))
        XCTAssertFalse(plan.matches(targetTime: 121, readySince: 10,
            seekGeneration: 1, surfaceGeneration: 1))
    }

    func testInitRejectsInvalidAndOverflowValues() {
        XCTAssertNotNil(makeDeadline(targetTime: 0, readySince: 0, settleDelay: 0))
        XCTAssertNil(UserSeekRevealDeadline(targetTime: -1, readySince: 10,
            settleDelay: 0.12, seekGeneration: 1, surfaceGeneration: 1))
        XCTAssertNil(UserSeekRevealDeadline(targetTime: .nan, readySince: 10,
            settleDelay: 0.12, seekGeneration: 1, surfaceGeneration: 1))
        XCTAssertNil(UserSeekRevealDeadline(targetTime: .infinity, readySince: 10,
            settleDelay: 0.12, seekGeneration: 1, surfaceGeneration: 1))
        XCTAssertNil(UserSeekRevealDeadline(targetTime: 120, readySince: .nan,
            settleDelay: 0.12, seekGeneration: 1, surfaceGeneration: 1))
        XCTAssertNil(UserSeekRevealDeadline(targetTime: 120, readySince: .infinity,
            settleDelay: 0.12, seekGeneration: 1, surfaceGeneration: 1))
        XCTAssertNil(UserSeekRevealDeadline(targetTime: 120, readySince: 10,
            settleDelay: -0.01, seekGeneration: 1, surfaceGeneration: 1))
        XCTAssertNil(UserSeekRevealDeadline(targetTime: 120, readySince: 10,
            settleDelay: .nan, seekGeneration: 1, surfaceGeneration: 1))
        XCTAssertNil(UserSeekRevealDeadline(targetTime: 120, readySince: 10,
            settleDelay: .infinity, seekGeneration: 1, surfaceGeneration: 1))
        XCTAssertNil(UserSeekRevealDeadline(
            targetTime: 120,
            readySince: .greatestFiniteMagnitude,
            settleDelay: .greatestFiniteMagnitude,
            seekGeneration: 1,
            surfaceGeneration: 1
        ))
    }
}
