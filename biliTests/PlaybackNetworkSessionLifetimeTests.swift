import XCTest
@testable import bili

final class PlaybackNetworkSessionLifetimeTests: XCTestCase {
    func testProbeBorrowedBeforePathChangeCanCreateTaskAfterRefresh() async throws {
        let pool = makePool()
        let lease = pool.playbackProbeSessionLease()
        pool.refreshForNetworkPathChange()

        let (data, response) = try await BiliNetworkRetry.data(
            sessionProvider: { lease },
            request: request(),
            policy: .playbackProbe
        )

        XCTAssertEqual(data, Data("ok".utf8))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertFalse(lease === pool.playbackProbeSessionLease())
    }

    func testBufferedPlaybackBorrowSurvivesPathChange() async throws {
        let pool = makePool()
        let lease = pool.playbackDataSessionLease()
        defer { withExtendedLifetime(lease) {} }
        pool.refreshForNetworkPathChange()

        let (data, response) = try await lease.session.data(for: request())

        XCTAssertEqual(data, Data("ok".utf8))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertFalse(lease === pool.playbackDataSessionLease())
    }

    func testRetiredSessionIsInvalidatedAfterLastBorrowerReleasesIt() async {
        let invalidated = expectation(description: "Retired session invalidated")
        let observer = RetiredSessionObserver(invalidated: invalidated)
        let pool = BiliPlaybackNetworkSessionPool(
            dataSessionFactory: { Self.makeSession() },
            probeSessionFactory: { Self.makeSession(delegate: observer) }
        )
        var lease: BiliPlaybackNetworkSessionLease? = pool.playbackProbeSessionLease()
        lease?.session.sessionDescription = "retired"

        pool.refreshForNetworkPathChange()
        XCTAssertFalse(observer.didInvalidate)
        withExtendedLifetime(lease) {}
        lease = nil

        await fulfillment(of: [invalidated], timeout: 3)
        XCTAssertTrue(observer.didInvalidate)
    }

    func testConcurrentRefreshesDoNotInvalidateBorrowedRequests() async throws {
        let pool = makePool()
        let request = request()
        try await withThrowingTaskGroup(of: Data.self) { group in
            for _ in 0..<24 {
                group.addTask {
                    let lease = pool.playbackProbeSessionLease()
                    pool.refreshForNetworkPathChange()
                    let (data, _) = try await BiliNetworkRetry.data(
                        sessionProvider: { lease }, request: request, policy: .playbackProbe
                    )
                    return data
                }
            }
            var completed = 0
            for try await data in group {
                XCTAssertEqual(data, Data("ok".utf8))
                completed += 1
            }
            XCTAssertEqual(completed, 24)
        }
    }

    private func makePool() -> BiliPlaybackNetworkSessionPool {
        BiliPlaybackNetworkSessionPool(
            dataSessionFactory: { Self.makeSession() },
            probeSessionFactory: { Self.makeSession() }
        )
    }

    private func request() -> URLRequest {
        var request = URLRequest(url: URL(string: "https://session-lifetime.invalid/probe")!)
        request.timeoutInterval = 3
        return request
    }

    private static func makeSession(delegate: URLSessionDelegate? = nil) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SessionLifetimeURLProtocol.self]
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }
}

private final class SessionLifetimeURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "session-lifetime.invalid"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("ok".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class RetiredSessionObserver: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var invalidationObserved = false
    private let invalidated: XCTestExpectation

    init(invalidated: XCTestExpectation) {
        self.invalidated = invalidated
    }

    var didInvalidate: Bool {
        lock.lock()
        defer { lock.unlock() }
        return invalidationObserved
    }

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        guard session.sessionDescription == "retired" else { return }
        lock.lock()
        invalidationObserved = true
        lock.unlock()
        invalidated.fulfill()
    }
}
