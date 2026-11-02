import Foundation
import XCTest
@testable import bili

@MainActor
final class PlaybackAudioSessionTests: XCTestCase {
    func testDeactivationLeavesMainActorFreeAndActivationWaitsForIt() async throws {
        let held = HeldAudioDeactivation()
        defer { held.release() }
        var activationCount = 0
        var completed = false
        let session = PlaybackAudioSession(deactivate: { held.run() }, activate: {
            activationCount += 1
            return true
        })
        session.deactivate { duration, succeeded in
            XCTAssertGreaterThanOrEqual(duration, 0)
            XCTAssertTrue(succeeded)
            completed = true
        }
        try await wait { held.started }
        XCTAssertFalse(held.ranOnMainThread)
        session.activate(when: { true }) { _ in }
        await Task.yield()
        XCTAssertFalse(completed)
        XCTAssertEqual(activationCount, 0)
        held.release()
        try await wait { completed && activationCount == 1 }
        XCTAssertFalse(session.isDeactivating)
    }

    func testNewPauseInvalidatesPendingPlayWithoutQueuingAnotherOldDeactivation() async throws {
        let held = HeldAudioDeactivation()
        defer { held.release() }
        var wantsPlayback = true
        var activationCount = 0
        let session = PlaybackAudioSession(deactivate: { held.run() }, activate: {
            activationCount += 1
            return true
        })
        session.deactivate { _, _ in }
        try await wait { held.started }
        session.activate(when: { wantsPlayback }) { _ in XCTFail("Paused playback cannot resume") }
        wantsPlayback = false
        session.deactivate { _, _ in XCTFail("An in-flight deactivation must be coalesced") }
        held.release()
        try await wait { !session.isDeactivating }
        // Drain the pending activation task as well.
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(activationCount, 0)
        XCTAssertEqual(held.callCount, 1)
    }

    func testHandoffActivatesOnlyTheNewOwnerAfterOldDeactivationFinishes() async throws {
        let held = HeldAudioDeactivation()
        defer { held.release() }
        var owner = "old"
        var activationCount = 0
        var newOwnerReady = false
        let session = PlaybackAudioSession(deactivate: { held.run() }, activate: {
            activationCount += 1
            return true
        })
        session.deactivate { _, _ in }
        try await wait { held.started }
        session.activate(when: { owner == "old" }) { _ in XCTFail("Old player cannot activate") }
        owner = "new"
        session.activate(when: { owner == "new" }) { _ in newOwnerReady = true }
        held.release()
        try await wait { newOwnerReady }
        XCTAssertEqual(activationCount, 1)
    }

    func testFailedDeactivationDoesNotLeaveActivationBlocked() async throws {
        var deactivationSucceeded: Bool?
        var activated = false
        let session = PlaybackAudioSession(deactivate: { false }, activate: { true })
        session.deactivate { _, succeeded in deactivationSucceeded = succeeded }
        session.activate(when: { true }) { succeeded in activated = succeeded }
        try await wait { activated }
        XCTAssertEqual(deactivationSucceeded, false)
        XCTAssertFalse(session.isDeactivating)
    }

    private func wait(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !predicate(), Date() < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(predicate(), "Audio-session operation did not complete")
    }
}

/// Only the worker waits; tests can keep issuing main-actor pause/play commands.
final class HeldAudioDeactivation: @unchecked Sendable {
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private var calls = 0
    private var onMain = false
    var callCount: Int { lock.withLock { calls } }
    var started: Bool { callCount > 0 }
    var ranOnMainThread: Bool { lock.withLock { onMain } }

    func run() -> Bool {
        lock.withLock { calls += 1; onMain = Thread.isMainThread }
        return gate.wait(timeout: .now() + 5) == .success
    }

    func release() { gate.signal() }
}
