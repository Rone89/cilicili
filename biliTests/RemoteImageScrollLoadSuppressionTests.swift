import SwiftUI
import XCTest
@testable import bili

final class RemoteImageScrollLoadSuppressionTests: XCTestCase {
    private var previousDiagnosticsEnabled = false

    override func setUp() {
        super.setUp()
        previousDiagnosticsEnabled = RemoteImageDiagnosticsRuntime.shared.isEnabled
        RemoteImageDiagnosticsRuntime.shared.setEnabled(true)
    }

    override func tearDown() {
        RemoteImageDiagnosticsRuntime.shared.setEnabled(previousDiagnosticsEnabled)
        super.tearDown()
    }

    func testPolicySuppressesInteractiveAndDeceleratingScroll() {
        XCTAssertTrue(FastScrollImageLoadSuppressionPolicy.suppressesNetworkLoads(
            phase: .interacting
        ))
        XCTAssertTrue(FastScrollImageLoadSuppressionPolicy.suppressesNetworkLoads(
            phase: .decelerating
        ))
        XCTAssertFalse(FastScrollImageLoadSuppressionPolicy.suppressesNetworkLoads(
            phase: .idle
        ))
    }

    func testCachedImageNeverWaitsForScrollToBecomeIdle() async {
        let gate = RemoteImageLoadSuppressionGate()
        let scopeID = UUID()
        await gate.setSuppressed(true, for: scopeID)

        await gate.waitUntilAllowed(priority: .prefetch, hasCachedImage: true)

        let waiterCount = await gate.waiterCountForTesting()
        XCTAssertEqual(waiterCount, 0)
        await gate.setSuppressed(false, for: scopeID)
    }

    func testVisibleNetworkLoadBypassesSuppression() async {
        let gate = RemoteImageLoadSuppressionGate()
        let scopeID = UUID()
        await gate.setSuppressed(true, for: scopeID)

        await gate.waitUntilAllowed(priority: .visible)

        let waiterCount = await gate.waiterCountForTesting()
        let statistics = await gate.statistics()
        XCTAssertEqual(waiterCount, 0)
        XCTAssertEqual(statistics.visibleBypassCount, 1)
        XCTAssertEqual(statistics.deferredPrefetchCount, 0)
        await gate.setSuppressed(false, for: scopeID)
    }

    func testNetworkLoadResumesAfterSuppressionEnds() async throws {
        let gate = RemoteImageLoadSuppressionGate()
        let scopeID = UUID()
        await gate.setSuppressed(true, for: scopeID)

        let waiter = Task {
            await gate.waitUntilAllowed(priority: .prefetch)
        }

        // Task.yield is advisory: a fixed number of yields need not schedule
        // the waiter on a loaded runner. Observe registration before releasing.
        let deadline = ContinuousClock.now + .seconds(3)
        var waiterCount = await gate.waiterCountForTesting()
        while waiterCount == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
            waiterCount = await gate.waiterCountForTesting()
        }
        XCTAssertEqual(waiterCount, 1)

        await gate.setSuppressed(false, for: scopeID)
        await waiter.value

        let resumedWaiterCount = await gate.waiterCountForTesting()
        XCTAssertEqual(resumedWaiterCount, 0)

        let statistics = await gate.statistics()
        XCTAssertEqual(statistics.deferredPrefetchCount, 1)
    }
}
