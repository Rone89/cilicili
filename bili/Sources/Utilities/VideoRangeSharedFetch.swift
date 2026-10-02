import Foundation

nonisolated enum VideoRangeFetchLeaseError: Error, Equatable, Sendable {
    case invalidSlice(offset: Int, length: Int?)
}

nonisolated fileprivate final class VideoRangeFetchWaiter: @unchecked Sendable {
    enum State {
        case prepared
        case waiting
        case cancelled
        case finished
    }

    let id = UUID()
    let leaseID: UUID
    let offset: Int
    let length: Int?
    var state: State = .prepared
    var continuation: CheckedContinuation<Data, Error>?
    var resolvedResult: Result<Data, Error>?

    init(leaseID: UUID, offset: Int, length: Int?) {
        self.leaseID = leaseID
        self.offset = offset
        self.length = length
    }
}

nonisolated final class VideoRangeSharedFetch: @unchecked Sendable {
    private typealias Completion = @Sendable (Result<Data, Error>) async -> Void

    private let lock = NSLock()
    private let hasExternalOwner: Bool
    private var registeredLeases = Set<UUID>()
    private var waiters: [UUID: VideoRangeFetchWaiter] = [:]
    private var publishedResult: Result<Data, Error>?
    private var isFinishing = false
    private var startWasCalled = false
    private var cancellationRequested = false
    private var producerTask: Task<Void, Never>?
    private var completionHandler: Completion?

    init(hasExternalOwner: Bool = false) {
        self.hasExternalOwner = hasExternalOwner
    }

    var isJoinable: Bool {
        lock.lock()
        let joinable =
            publishedResult == nil
                && !cancellationRequested
                && (hasExternalOwner || !registeredLeases.isEmpty)
        lock.unlock()
        return joinable
    }

    func makeLease(offset: Int = 0, length: Int? = nil) -> VideoRangeFetchLease {
        let leaseID = UUID()
        lock.lock()
        if publishedResult == nil, !cancellationRequested {
            registeredLeases.insert(leaseID)
        }
        lock.unlock()
        return VideoRangeFetchLease(
            fetch: self,
            leaseID: leaseID,
            offset: offset,
            length: length
        )
    }

    /// Joining and retaining a consumer must be atomic with last-consumer cancellation.
    func joinLease(offset: Int = 0, length: Int? = nil) -> VideoRangeFetchLease? {
        let leaseID = UUID()
        lock.lock()
        guard publishedResult == nil, !cancellationRequested,
              hasExternalOwner || !registeredLeases.isEmpty
        else {
            lock.unlock()
            return nil
        }
        registeredLeases.insert(leaseID)
        lock.unlock()
        return VideoRangeFetchLease(fetch: self, leaseID: leaseID, offset: offset, length: length)
    }

    func start(
        loader: @escaping @Sendable () async throws -> Data,
        onComplete: @escaping @Sendable (Result<Data, Error>) async -> Void
    ) {
        var callbackResult: Result<Data, Error>?
        var callbackToSchedule: Completion?
        var shouldStartLoader = false

        lock.lock()
        guard !startWasCalled else {
            lock.unlock()
            return
        }
        startWasCalled = true
        completionHandler = onComplete

        if let publishedResult {
            callbackResult = publishedResult
            callbackToSchedule = completionHandler
            completionHandler = nil
        } else if !cancellationRequested {
            let hasConsumer = hasExternalOwner || !registeredLeases.isEmpty
            if hasConsumer {
                shouldStartLoader = true
            } else {
                cancellationRequested = true
            }
        }
        lock.unlock()

        if let callbackResult, let callbackToSchedule {
            scheduleCompletionCallback(callbackToSchedule, result: callbackResult)
            return
        }

        guard shouldStartLoader else {
            beginCompletion(.failure(CancellationError()))
            return
        }

        let task = Task.detached(priority: .userInitiated) { [weak self, loader] in
            guard let self, self.shouldRunProducer() else { return }

            let result: Result<Data, Error>
            do {
                result = .success(try await loader())
            } catch {
                result = .failure(error)
            }
            self.producerFinished(result)
        }

        var attached = false
        lock.lock()
        if publishedResult == nil,
           !isFinishing,
           !cancellationRequested,
           hasExternalOwner || !registeredLeases.isEmpty {
            producerTask = task
            attached = true
        } else if publishedResult == nil, !isFinishing {
            cancellationRequested = true
        }
        lock.unlock()

        guard !attached else { return }
        task.cancel()
        beginCompletion(.failure(CancellationError()))
    }

    func complete(_ result: Result<Data, Error>) {
        beginCompletion(result)
    }

    func cancel() {
        var task: Task<Void, Never>?
        lock.lock()
        guard publishedResult == nil, !isFinishing else {
            lock.unlock()
            return
        }
        cancellationRequested = true
        task = producerTask
        lock.unlock()

        task?.cancel()
        beginCompletion(.failure(CancellationError()))
    }

    private func shouldRunProducer() -> Bool {
        lock.lock()
        let shouldRun =
            publishedResult == nil
                && !isFinishing
                && !cancellationRequested
                && (hasExternalOwner || !registeredLeases.isEmpty)
        lock.unlock()
        return shouldRun
    }

    private func producerFinished(_ result: Result<Data, Error>) {
        beginCompletion(result)
    }

    private func beginCompletion(_ proposedResult: Result<Data, Error>) {
        var finalResult = proposedResult
        var callback: Completion?

        lock.lock()
        guard publishedResult == nil, !isFinishing else {
            lock.unlock()
            return
        }
        if cancellationRequested {
            finalResult = .failure(CancellationError())
        }
        isFinishing = true
        producerTask = nil
        callback = completionHandler
        completionHandler = nil
        lock.unlock()

        if let callback {
            scheduleCompletionCallback(callback, result: finalResult)
        } else {
            publish(finalResult)
        }
    }

    private func scheduleCompletionCallback(_ callback: @escaping Completion, result: Result<Data, Error>) {
        Task.detached(priority: nil) { [weak self] in
            await callback(result)
            self?.publish(result)
        }
    }

    private func publish(_ result: Result<Data, Error>) {
        var continuations: [(CheckedContinuation<Data, Error>, Result<Data, Error>)] = []

        lock.lock()
        guard publishedResult == nil else {
            lock.unlock()
            return
        }
        publishedResult = result
        isFinishing = false
        producerTask = nil
        completionHandler = nil
        registeredLeases.removeAll(keepingCapacity: false)

        for waiter in waiters.values {
            let waiterResult = slicedResult(
                result,
                offset: waiter.offset,
                length: waiter.length
            )
            switch waiter.state {
            case .prepared:
                waiter.state = .finished
                waiter.resolvedResult = waiterResult
            case .waiting:
                waiter.state = .finished
                let continuation = waiter.continuation
                waiter.continuation = nil
                if let continuation {
                    continuations.append((continuation, waiterResult))
                }
            case .cancelled, .finished:
                break
            }
        }
        waiters.removeAll(keepingCapacity: false)
        lock.unlock()

        for (continuation, waiterResult) in continuations {
            continuation.resume(with: waiterResult)
        }
    }

    fileprivate func prepare(_ waiter: VideoRangeFetchWaiter) -> Bool {
        var shouldCancelProducer = false
        let taskWasCancelled = Task.isCancelled

        lock.lock()
        if taskWasCancelled {
            waiter.state = .cancelled
            shouldCancelProducer = removeLeaseIfUnusedLocked(waiter.leaseID)
        } else {
            if publishedResult == nil, !cancellationRequested {
                registeredLeases.insert(waiter.leaseID)
            }
            waiters[waiter.id] = waiter
        }
        lock.unlock()

        if shouldCancelProducer {
            cancel()
        }
        return taskWasCancelled
    }

    fileprivate func awaitValue(_ waiter: VideoRangeFetchWaiter) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            var immediateResult: Result<Data, Error>?
            var shouldCancelProducer = false

            lock.lock()
            switch waiter.state {
            case .cancelled:
                immediateResult = .failure(CancellationError())
            case .finished:
                immediateResult = waiter.resolvedResult ?? .failure(CancellationError())
            case .prepared, .waiting:
                if Task.isCancelled {
                    waiter.state = .cancelled
                    waiter.continuation = nil
                    waiters.removeValue(forKey: waiter.id)
                    shouldCancelProducer = removeLeaseIfUnusedLocked(waiter.leaseID)
                    immediateResult = .failure(CancellationError())
                } else if let publishedResult {
                    waiter.state = .finished
                    waiters.removeValue(forKey: waiter.id)
                    immediateResult = slicedResult(
                        publishedResult,
                        offset: waiter.offset,
                        length: waiter.length
                    )
                } else {
                    waiter.state = .waiting
                    waiter.continuation = continuation
                    lock.unlock()
                    return
                }
            }
            lock.unlock()

            if shouldCancelProducer {
                cancel()
            }
            continuation.resume(with: immediateResult ?? .failure(CancellationError()))
        }
    }

    fileprivate func cancel(_ waiter: VideoRangeFetchWaiter) {
        var continuation: CheckedContinuation<Data, Error>?
        var shouldCancelProducer = false

        lock.lock()
        switch waiter.state {
        case .prepared, .waiting:
            waiter.state = .cancelled
            continuation = waiter.continuation
            waiter.continuation = nil
            waiters.removeValue(forKey: waiter.id)
            shouldCancelProducer = removeLeaseIfUnusedLocked(waiter.leaseID)
        case .cancelled, .finished:
            break
        }
        lock.unlock()

        continuation?.resume(throwing: CancellationError())
        if shouldCancelProducer {
            cancel()
        }
    }

    fileprivate func releaseLease(_ leaseID: UUID) {
        var shouldCancelProducer = false

        lock.lock()
        if !hasWaitingWaiterLocked(for: leaseID) {
            shouldCancelProducer = removeLeaseIfUnusedLocked(leaseID)
        }
        lock.unlock()

        if shouldCancelProducer {
            cancel()
        }
    }

    private func hasWaitingWaiterLocked(for leaseID: UUID) -> Bool {
        waiters.values.contains { waiter in
            waiter.leaseID == leaseID && (waiter.state == .prepared || waiter.state == .waiting)
        }
    }

    private func removeLeaseIfUnusedLocked(_ leaseID: UUID) -> Bool {
        guard !hasWaitingWaiterLocked(for: leaseID) else { return false }
        guard registeredLeases.remove(leaseID) != nil else { return false }
        let shouldCancel = publishedResult == nil
            && !isFinishing
            && !hasExternalOwner
            && registeredLeases.isEmpty
        if shouldCancel {
            cancellationRequested = true
        }
        return shouldCancel
    }

    private func slicedResult(
        _ result: Result<Data, Error>,
        offset: Int,
        length: Int?
    ) -> Result<Data, Error> {
        result.flatMap { data in
            guard offset >= 0,
                  offset <= data.count,
                  length.map({ $0 >= 0 }) ?? true
            else {
                return .failure(VideoRangeFetchLeaseError.invalidSlice(offset: offset, length: length))
            }

            let availableLength = data.count - offset
            let sliceLength = length ?? availableLength
            guard sliceLength <= availableLength else {
                return .failure(VideoRangeFetchLeaseError.invalidSlice(offset: offset, length: length))
            }
            if offset == 0, sliceLength == data.count { return .success(data) }
            return .success(data.subdata(in: offset..<(offset + sliceLength)))
        }
    }
}

nonisolated final class VideoRangeFetchLease: @unchecked Sendable {
    private let fetch: VideoRangeSharedFetch
    private let leaseID: UUID
    private let offset: Int
    private let length: Int?

    fileprivate init(fetch: VideoRangeSharedFetch, leaseID: UUID, offset: Int, length: Int?) {
        self.fetch = fetch
        self.leaseID = leaseID
        self.offset = offset
        self.length = length
    }

    deinit {
        fetch.releaseLease(leaseID)
    }

    var value: Data {
        get async throws {
            let waiter = VideoRangeFetchWaiter(
                leaseID: leaseID,
                offset: offset,
                length: length
            )
            if fetch.prepare(waiter) {
                throw CancellationError()
            }
            return try await withTaskCancellationHandler(operation: {
                try await fetch.awaitValue(waiter)
            }, onCancel: {
                fetch.cancel(waiter)
            })
        }
    }
}
