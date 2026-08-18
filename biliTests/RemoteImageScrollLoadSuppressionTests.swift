import SwiftUI
import XCTest
@testable import bili

final class RemoteImageScrollLoadSuppressionTests: XCTestCase {
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

    func testNetworkLoadResumesAfterSuppressionEnds() async {
        let gate = RemoteImageLoadSuppressionGate()
        let scopeID = UUID()
        await gate.setSuppressed(true, for: scopeID)

        let waiter = Task {
            await gate.waitUntilAllowed(priority: .prefetch)
        }

        var waiterCount = 0
        for _ in 0..<20 {
            waiterCount = await gate.waiterCountForTesting()
            guard waiterCount == 0 else { break }
            await Task.yield()
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
