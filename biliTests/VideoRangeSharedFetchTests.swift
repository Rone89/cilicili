import Foundation
import XCTest

@testable import bili

final class VideoRangeSharedFetchTests: XCTestCase {
    func testOnlyConsumerCancellationCancelsLoaderAndReturnsCancellation() async {
        let fetch = VideoRangeSharedFetch()
        let lease = fetch.makeLease()
        let gate = ThrowingGate()
        let loaderStarted = expectation(description: "loader started")
        let loaderCancelled = expectation(description: "loader cancelled")
        let completionCalled = expectation(description: "completion called")
        let completionCount = LockedCounter()

        fetch.start(loader: {
            loaderStarted.fulfill()
            do {
                try await gate.wait()
                return Data([1])
            } catch {
                loaderCancelled.fulfill()
                throw error
            }
        }, onComplete: { _ in
            completionCount.increment()
            completionCalled.fulfill()
        })

        await fulfillment(of: [loaderStarted], timeout: 1)
        let consumer = Task { () -> Bool in
            do {
                _ = try await lease.value
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }
        consumer.cancel()

        let received1 = await consumer.value
        XCTAssertTrue(received1)
        XCTAssertFalse(fetch.isJoinable)
        await fulfillment(of: [loaderCancelled, completionCalled], timeout: 1)
        XCTAssertEqual(completionCount.value, 1)
    }

    func testCanceledLoserDoesNotCancelProducerNeededByAnotherConsumer() async throws {
        let fetch = VideoRangeSharedFetch()
        let winnerLease = fetch.makeLease()
        let loserLease = fetch.makeLease()
        let gate = ThrowingGate()
        let loaderStarted = expectation(description: "loader started")

        fetch.start(loader: {
            loaderStarted.fulfill()
            try await gate.wait()
            return Data([4, 5, 6])
        }, onComplete: { _ in })

        await fulfillment(of: [loaderStarted], timeout: 1)
        let winner = Task { try? await winnerLease.value }
        let loser = Task { () -> Bool in
            do {
                _ = try await loserLease.value
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }
        loser.cancel()

        let received2 = await loser.value
        XCTAssertTrue(received2)
        XCTAssertTrue(fetch.isJoinable)
        gate.open()

        let received3 = await winner.value
        XCTAssertEqual(received3, Data([4, 5, 6]))
    }

    func testCanceledJoinedConsumerLeavesExternalOwnerJoinable() async throws {
        let fetch = VideoRangeSharedFetch(hasExternalOwner: true)
        let canceledLease = fetch.makeLease()
        let consumer = Task { () -> Bool in
            do {
                _ = try await canceledLease.value
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }
        consumer.cancel()

        let received4 = await consumer.value
        XCTAssertTrue(received4)
        XCTAssertTrue(fetch.isJoinable)

        let joinedLease = fetch.makeLease(offset: 1, length: 2)
        fetch.complete(.success(Data([10, 20, 30, 40])))
        let received5 = try await joinedLease.value
        XCTAssertEqual(received5, Data([20, 30]))
    }

    func testCanceledContainingLeaseDoesNotCancelExternalOwner() async throws {
        let fetch = VideoRangeSharedFetch(hasExternalOwner: true)
        let containingLease = fetch.makeLease(offset: 1, length: 2)
        let consumer = Task { () -> Bool in
            do {
                _ = try await containingLease.value
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }
        consumer.cancel()

        let received6 = await consumer.value
        XCTAssertTrue(received6)
        XCTAssertTrue(fetch.isJoinable)

        let remainingLease = fetch.makeLease()
        fetch.complete(.success(Data([7, 8])))
        let received7 = try await remainingLease.value
        XCTAssertEqual(received7, Data([7, 8]))
    }

    func testCancellationBeforeStartPreventsLoaderAttachment() async {
        let fetch = VideoRangeSharedFetch()
        let lease = fetch.makeLease()
        let consumer = Task { () -> Bool in
            do {
                _ = try await lease.value
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }
        consumer.cancel()

        let received8 = await consumer.value
        XCTAssertTrue(received8)
        XCTAssertFalse(fetch.isJoinable)

        let loaderCalls = LockedCounter()
        let completionCalled = expectation(description: "completion called")
        fetch.start(loader: {
            loaderCalls.increment()
            return Data([1])
        }, onComplete: { _ in
            completionCalled.fulfill()
        })

        await fulfillment(of: [completionCalled], timeout: 1)
        XCTAssertEqual(loaderCalls.value, 0)
    }

    func testAbandoningUnawaitedLeaseCancelsGeneration() async {
        let fetch = VideoRangeSharedFetch()
        var lease: VideoRangeFetchLease? = fetch.makeLease()
        XCTAssertNotNil(lease)
        XCTAssertTrue(fetch.isJoinable)

        lease = nil

        XCTAssertFalse(fetch.isJoinable)
        let loaderCalls = LockedCounter()
        let completionCalled = expectation(description: "completion called")
        fetch.start(loader: {
            loaderCalls.increment()
            return Data([1])
        }, onComplete: { _ in
            completionCalled.fulfill()
        })

        await fulfillment(of: [completionCalled], timeout: 1)
        XCTAssertEqual(loaderCalls.value, 0)
    }

    func testLastLeaseRemovalCannotBeResurrectedByAReplacementLease() async throws {
        let fetch = VideoRangeSharedFetch()
        var originalLease: VideoRangeFetchLease? = fetch.makeLease()
        XCTAssertNotNil(originalLease)
        originalLease = nil

        XCTAssertFalse(fetch.isJoinable)
        let replacementLease = fetch.makeLease()
        XCTAssertFalse(fetch.isJoinable)

        fetch.start(loader: { Data([1]) }, onComplete: { _ in })
        do {
            _ = try await replacementLease.value
            XCTFail("a replacement lease must not resurrect a cancelled generation")
        } catch is CancellationError {
            // Expected.
        }
    }

    func testAtomicJoinRetainsProducerAndRejectsCancelledGeneration() async throws {
        let fetch = VideoRangeSharedFetch()
        var original: VideoRangeFetchLease? = fetch.makeLease()
        XCTAssertNotNil(original)
        let joined = try XCTUnwrap(fetch.joinLease())
        original = nil
        XCTAssertTrue(fetch.isJoinable)
        fetch.complete(.success(Data([3])))
        let data = try await joined.value
        XCTAssertEqual(data, Data([3]))

        let cancelled = VideoRangeSharedFetch()
        var abandoned: VideoRangeFetchLease? = cancelled.makeLease()
        XCTAssertNotNil(abandoned)
        abandoned = nil
        XCTAssertNil(cancelled.joinLease())
    }

    func testSuccessfulFinishingGenerationRemainsJoinableUntilCallbackPublishes() async throws {
        let fetch = VideoRangeSharedFetch()
        let firstLease = fetch.makeLease()
        let callbackGate = ThrowingGate()
        let callbackStarted = expectation(description: "completion callback started")

        fetch.start(loader: { Data([2, 3, 4]) }, onComplete: { _ in
            callbackStarted.fulfill()
            try? await callbackGate.wait()
        })

        await fulfillment(of: [callbackStarted], timeout: 1)
        XCTAssertTrue(fetch.isJoinable)
        let joinedLease = fetch.makeLease(offset: 1, length: 2)
        callbackGate.open()

        let received9 = try await firstLease.value
        XCTAssertEqual(received9, Data([2, 3, 4]))
        let received10 = try await joinedLease.value
        XCTAssertEqual(received10, Data([3, 4]))
    }

    func testLoaderErrorRunsCompletionAndIsDeliveredToLease() async {
        let fetch = VideoRangeSharedFetch()
        let lease = fetch.makeLease()
        let completionCalled = expectation(description: "completion called")
        let completionCount = LockedCounter()
        let error = TestFetchError.loader

        fetch.start(loader: {
            throw error
        }, onComplete: { result in
            if case let .failure(receivedError) = result {
                XCTAssertEqual(receivedError as? TestFetchError, error)
            } else {
                XCTFail("completion should receive the loader error")
            }
            completionCount.increment()
            completionCalled.fulfill()
        })

        do {
            _ = try await lease.value
            XCTFail("loader error should be rethrown")
        } catch let receivedError as TestFetchError {
            XCTAssertEqual(receivedError, error)
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        await fulfillment(of: [completionCalled], timeout: 1)
        XCTAssertEqual(completionCount.value, 1)
    }

    func testInvalidSliceFailsWithoutSlicingOutOfBounds() async {
        let fetch = VideoRangeSharedFetch()
        let lease = fetch.makeLease(offset: 3, length: 3)
        fetch.start(loader: { Data([0, 1, 2, 3]) }, onComplete: { _ in })

        do {
            _ = try await lease.value
            XCTFail("invalid slice should throw")
        } catch let error as VideoRangeFetchLeaseError {
            XCTAssertEqual(error, .invalidSlice(offset: 3, length: 3))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testCompletionIsExactlyOnceAndCompletedResultCanBeAwaitedAgain() async throws {
        let fetch = VideoRangeSharedFetch(hasExternalOwner: true)
        let lease = fetch.makeLease()
        let loaderGate = ThrowingGate()
        let completionCalled = expectation(description: "completion called")
        let completionCount = LockedCounter()
        let completionResult = ResultRecorder()

        fetch.start(loader: {
            try await loaderGate.wait()
            return Data([9])
        }, onComplete: { result in
            completionCount.increment()
            completionResult.record(result)
            completionCalled.fulfill()
        })

        fetch.complete(.success(Data([5, 6])))
        fetch.complete(.failure(TestFetchError.loader))

        let received11 = try await lease.value
        XCTAssertEqual(received11, Data([5, 6]))
        let received12 = try await lease.value
        XCTAssertEqual(received12, Data([5, 6]))
        await fulfillment(of: [completionCalled], timeout: 1)
        XCTAssertEqual(completionCount.value, 1)
        XCTAssertEqual(completionResult.successfulData, Data([5, 6]))

        loaderGate.open()
    }
}

private enum TestFetchError: Error, Equatable, Sendable {
    case loader
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        let count = self.count
        lock.unlock()
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

private final class ResultRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<Data, Error>] = []

    func record(_ result: Result<Data, Error>) {
        lock.lock()
        results.append(result)
        lock.unlock()
    }

    var successfulData: Data? {
        lock.lock()
        let data = results.compactMap { result -> Data? in
            guard case let .success(data) = result else { return nil }
            return data
        }.first
        lock.unlock()
        return data
    }
}

private final class ThrowingGate: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Void, Error>?
    private var continuation: CheckedContinuation<Void, Error>?

    func wait() async throws {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                var immediateResult: Result<Void, Error>?
                lock.lock()
                if let result {
                    immediateResult = result
                } else if Task.isCancelled {
                    result = .failure(CancellationError())
                    immediateResult = result
                } else {
                    self.continuation = continuation
                }
                lock.unlock()

                if let immediateResult {
                    continuation.resume(with: immediateResult)
                }
            }
        }, onCancel: {
            cancel()
        })
    }

    func open() {
        finish(.success(()))
    }

    func cancel() {
        finish(.failure(CancellationError()))
    }

    private func finish(_ result: Result<Void, Error>) {
        var continuation: CheckedContinuation<Void, Error>?
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return
        }
        self.result = result
        continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}
