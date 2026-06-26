import Foundation
import Network

enum HLSRemoteRangeStreamer {
    nonisolated static func stream(
        range: HTTPByteRange,
        from url: URL,
        headers: [String: String],
        responseHeader: Data,
        connection: NWConnection,
        cacheLimit: Int64,
        startupChunkSize: Int = 32 * 1024,
        transform: HLSMediaSegmentTransform? = nil,
        onFirstChunkSent: (@Sendable (Int) async -> Void)? = nil
    ) async throws -> VideoRangeStreamCachePayload? {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = range.length > 1_500_000 ? 3.2 : 2.0
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.setValue("bytes=\(range.start)-\(range.endInclusive)", forHTTPHeaderField: "Range")

        let stream = HLSRemoteRangeStreamingSession.shared.start(request: request)
        defer {
            HLSRemoteRangeStreamingSession.shared.finish(task: stream.task)
        }

        let response: URLResponse
        do {
            response = try await stream.handler.response()
        } catch let error as URLError {
            throw HLSBridgeRemoteFailure.urlSession(error, url: url, range: range)
        } catch {
            throw error
        }
        try HLSRemoteRangeResponseValidator.validate(response, requestedRange: range, url: url)

        let cacheCollector = VideoRangeStreamCacheCollector(range: range, cacheLimit: cacheLimit)
        var didStartResponse = false
        do {
            let chunkSize = min(max(startupChunkSize, 24 * 1024), 96 * 1024)
            var chunk = Data()
            var didNotifyFirstChunk = false
            var didApplyTransform = false
            chunk.reserveCapacity(chunkSize)
            for try await data in stream.handler.chunks {
                try Task.checkCancellation()
                try cacheCollector?.append(data)
                chunk.append(data)
                if chunk.count >= chunkSize {
                    let outboundChunk: Data?
                    if let transform, !didApplyTransform {
                        let transformResult = transform.applyResult(to: chunk)
                        if transformResult.didNormalizeTiming {
                            outboundChunk = transformResult.data
                            didApplyTransform = true
                        } else {
                            outboundChunk = nil
                        }
                    } else {
                        outboundChunk = chunk
                    }
                    if let outboundChunk {
                        if !didStartResponse {
                            try await send(responseHeader, to: connection)
                            didStartResponse = true
                        }
                        try await send(outboundChunk, to: connection)
                        if !didNotifyFirstChunk {
                            didNotifyFirstChunk = true
                            await onFirstChunkSent?(outboundChunk.count)
                        }
                        chunk.removeAll(keepingCapacity: true)
                    }
                }
            }
            if !chunk.isEmpty {
                let outboundChunk: Data
                if let transform, !didApplyTransform {
                    let transformResult = transform.applyResult(to: chunk)
                    outboundChunk = transformResult.data
                    didApplyTransform = true
                } else {
                    outboundChunk = chunk
                }
                if !didStartResponse {
                    try await send(responseHeader, to: connection)
                    didStartResponse = true
                }
                try await send(outboundChunk, to: connection)
                if !didNotifyFirstChunk {
                    didNotifyFirstChunk = true
                    await onFirstChunkSent?(outboundChunk.count)
                }
            }
            guard didNotifyFirstChunk else {
                throw HLSBridgeRemoteFailure.emptyResponse(url: url, range: range)
            }
        } catch {
            stream.task.cancel()
            cacheCollector?.cancel()
            guard didStartResponse else { throw error }
            connection.cancel()
            throw HLSRangeStreamError.responseAlreadyStarted(error)
        }
        connection.cancel()
        return try cacheCollector?.finish()
    }

    private nonisolated static func send(_ data: Data, to connection: NWConnection) async throws {
        guard !data.isEmpty else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }
}

nonisolated enum PlaybackRangeStreamingSessionCoordinator {
    static func refreshForNetworkPathChange() {
        HLSRemoteRangeStreamingSession.shared.refreshForNetworkPathChange()
    }
}

private final class HLSRemoteRangeStreamingSession: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    static let shared = HLSRemoteRangeStreamingSession()

    private let lock = NSLock()
    private let delegateQueue: OperationQueue
    private lazy var session = URLSession(
        configuration: BiliURLSessionFactory.makePlaybackStreamingConfiguration(),
        delegate: self,
        delegateQueue: delegateQueue
    )
    private var handlers: [ObjectIdentifier: HLSRemoteRangeStreamHandler] = [:]

    private override init() {
        delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 2
        delegateQueue.qualityOfService = .userInitiated
        super.init()
    }

    func start(request: URLRequest) -> (task: URLSessionDataTask, handler: HLSRemoteRangeStreamHandler) {
        let handler = HLSRemoteRangeStreamHandler()
        lock.lock()
        let currentSession = session
        let task = currentSession.dataTask(with: request)
        handlers[ObjectIdentifier(task)] = handler
        lock.unlock()
        task.resume()
        return (task, handler)
    }

    func finish(task: URLSessionTask) {
        lock.lock()
        handlers[ObjectIdentifier(task)] = nil
        lock.unlock()
    }

    func refreshForNetworkPathChange() {
        let oldSession: URLSession
        lock.lock()
        oldSession = session
        session = URLSession(
            configuration: BiliURLSessionFactory.makePlaybackStreamingConfiguration(),
            delegate: self,
            delegateQueue: delegateQueue
        )
        lock.unlock()
        oldSession.finishTasksAndInvalidate()
    }

    func urlSession(
        _: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let handler = handler(for: dataTask) else {
            completionHandler(.cancel)
            return
        }
        handler.receive(response: response)
        completionHandler(.allow)
    }

    func urlSession(
        _: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        handler(for: dataTask)?.receive(data: data)
    }

    func urlSession(
        _: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        handler(for: task)?.complete(error: error)
        finish(task: task)
    }

    private func handler(for task: URLSessionTask) -> HLSRemoteRangeStreamHandler? {
        lock.lock()
        let handler = handlers[ObjectIdentifier(task)]
        lock.unlock()
        return handler
    }
}

private final class HLSRemoteRangeStreamHandler: @unchecked Sendable {
    let chunks: AsyncThrowingStream<Data, Error>

    private let lock = NSLock()
    private let chunkContinuation: AsyncThrowingStream<Data, Error>.Continuation
    private var responseContinuation: CheckedContinuation<URLResponse, Error>?
    private var responseResult: Result<URLResponse, Error>?

    init() {
        var continuation: AsyncThrowingStream<Data, Error>.Continuation?
        self.chunks = AsyncThrowingStream(Data.self, bufferingPolicy: .unbounded) { streamContinuation in
            continuation = streamContinuation
        }
        self.chunkContinuation = continuation!
    }

    func response() async throws -> URLResponse {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let responseResult {
                lock.unlock()
                continuation.resume(with: responseResult)
                return
            }
            responseContinuation = continuation
            lock.unlock()
        }
    }

    func receive(response: URLResponse) {
        completeResponse(.success(response))
    }

    func receive(data: Data) {
        chunkContinuation.yield(data)
    }

    func complete(error: Error?) {
        if let error {
            completeResponse(.failure(error))
            chunkContinuation.finish(throwing: error)
        } else {
            completeResponse(.failure(PlayerEngineError.unsupportedMedia))
            chunkContinuation.finish()
        }
    }

    private func completeResponse(_ result: Result<URLResponse, Error>) {
        lock.lock()
        guard responseResult == nil else {
            lock.unlock()
            return
        }
        responseResult = result
        let continuation = responseContinuation
        responseContinuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}

enum VideoRangeStreamCachePayload: Sendable {
    case data(Data)
    case file(URL)

    nonisolated var byteCount: Int {
        switch self {
        case let .data(data):
            return data.count
        case let .file(url):
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return size
        }
    }

    nonisolated func loadData() throws -> Data {
        switch self {
        case let .data(data):
            return data
        case let .file(url):
            return try Data(contentsOf: url, options: .mappedIfSafe)
        }
    }

    nonisolated func cleanup() {
        if case let .file(url) = self {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

nonisolated final class VideoRangeStreamCacheCollector: @unchecked Sendable {
    private let fileURL: URL?
    private var data: Data?
    private var handle: FileHandle?
    private var isFinished = false

    init?(range: HTTPByteRange, cacheLimit: Int64) {
        guard range.length <= cacheLimit else { return nil }
        if range.length > 1_500_000 {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("cc.bili.hls-stream-cache", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let candidateURL = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("tmp")
            FileManager.default.createFile(atPath: candidateURL.path, contents: nil)
            if let handle = try? FileHandle(forWritingTo: candidateURL) {
                self.fileURL = candidateURL
                self.handle = handle
                self.data = nil
            } else {
                self.fileURL = nil
                self.handle = nil
                self.data = Data()
            }
        } else {
            self.fileURL = nil
            self.handle = nil
            self.data = Data()
            self.data?.reserveCapacity(Int(range.length))
        }
    }

    func append(_ chunk: Data) throws {
        if let handle {
            try handle.write(contentsOf: chunk)
        } else {
            data?.append(chunk)
        }
    }

    func finish() throws -> VideoRangeStreamCachePayload? {
        guard !isFinished else { return nil }
        isFinished = true
        if let handle {
            try handle.close()
            self.handle = nil
        }
        if let fileURL {
            return .file(fileURL)
        }
        if let data {
            return .data(data)
        }
        return nil
    }

    func cancel() {
        guard !isFinished else { return }
        isFinished = true
        try? handle?.close()
        handle = nil
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        data = nil
    }

    deinit {
        cancel()
    }
}
