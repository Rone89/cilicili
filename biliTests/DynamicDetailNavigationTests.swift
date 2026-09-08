import Foundation
import XCTest

@testable import bili

final class DynamicDetailNavigationTests: XCTestCase {
    override func tearDown() {
        DynamicDetailURLProtocol.reset()
        super.tearDown()
    }

    @MainActor
    func testSupportsDetailNavigationForOriginalContentKinds() throws {
        let textOriginal = try decodeOriginal(
            #"{"id_str":"text","type":"DYNAMIC_TYPE_WORD","modules":{"module_dynamic":{"desc":{"text":"plain text"}}}}"#
        )
        XCTAssertTrue(DynamicFeedCardDisplayModel.supportsDetailNavigation(original: textOriginal))

        let imageOriginal = try decodeOriginal(
            #"{"id_str":"image","type":"DYNAMIC_TYPE_DRAW","modules":{"module_dynamic":{"major":{"draw":{"items":[{"src":"https://i.example.com/image.jpg","width":100,"height":100}]}}}}}"#
        )
        XCTAssertTrue(DynamicFeedCardDisplayModel.supportsDetailNavigation(original: imageOriginal))

        let videoOriginal = try decodeOriginal(
            #"{"id_str":"video","type":"DYNAMIC_TYPE_AV","modules":{"module_dynamic":{"major":{"archive":{"bvid":"BV1xx411c7mD","title":"video"}}}}}"#
        )
        XCTAssertFalse(DynamicFeedCardDisplayModel.supportsDetailNavigation(original: videoOriginal))

        let liveOriginal = try decodeOriginal(
            #"{"id_str":"live","type":"DYNAMIC_TYPE_LIVE_RCMD","modules":{"module_dynamic":{"major":{"live":{"room_id":123,"title":"live"}}}}}"#
        )
        XCTAssertFalse(DynamicFeedCardDisplayModel.supportsDetailNavigation(original: liveOriginal))
    }

    @MainActor
    func testFetchDynamicDetailUsesDetailRouteQueryAndDecodesItem() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let recorder = DynamicDetailRequestRecorder()
        let requestExpectation = expectation(description: "dynamic detail request captured")
        DynamicDetailURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return dynamicDetailResponse(
                for: request,
                body: """
                {"code":0,"data":{"item":{"id_str":"dynamic-detail-123","type":"DYNAMIC_TYPE_WORD","modules":{"module_dynamic":{"desc":{"text":"decoded detail"}},"module_stat":{"like":{"count":42,"status":true}}}}}}
                """
            )
        }

        let api = try makeAPI()
        let item = try await api.fetchDynamicDetail(id: "dynamic-detail-123")

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(item.idStr, "dynamic-detail-123")
        XCTAssertEqual(item.displayText, "decoded detail")
        XCTAssertTrue(item.isLiked)
        XCTAssertEqual(item.likeCount, 42)

        let request = try XCTUnwrap(recorder.request)
        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(url.host, "api.bilibili.com")
        XCTAssertEqual(url.path, "/x/polymer/web-dynamic/v1/detail")
        XCTAssertEqual(query["id"], "dynamic-detail-123")
        XCTAssertEqual(query["timezone_offset"], "-480")
        XCTAssertEqual(query["gaia_source"], "Athena")
        XCTAssertEqual(query["web_location"], "333.1330")
        XCTAssertEqual(
            query["x-bili-device-req-json"],
            #"{"platform":"web","device":"pc","spmid":"333.1330"}"#
        )
        XCTAssertEqual(
            query["features"],
            "itemOpusStyle,listOnlyfans,opusBigCover,onlyfansVote,decorationCard,onlyfansAssetsV2,forwardListHidden,ugcDelete"
        )
    }

    @MainActor
    func testCommentReloadKeepsLoadedCommentsWhenRefreshReturnsEmptyPage() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let responses = DynamicCommentsResponseSequence([
            .success(#"{"code":0,"data":{"replies":[{"rpid":101}],"top_replies":[],"cursor":{"is_end":true}}}"#),
            .success(#"{"code":0,"data":{"replies":[],"top_replies":[],"cursor":{"is_end":true}}}"#),
        ])
        DynamicCommentsURLProtocol.install { request in
            try responses.nextResponse(for: request)
        }
        defer { DynamicCommentsURLProtocol.reset() }

        let viewModel = DynamicCommentsViewModel(item: try makeCommentableItem(), api: try makeCommentsAPI())
        await viewModel.loadInitial()
        XCTAssertEqual(viewModel.comments.map(\.id), [101])

        await BiliAPIResponseMemoryCache.shared.clear()
        await viewModel.reload()

        XCTAssertEqual(viewModel.comments.map(\.id), [101])
        XCTAssertEqual(viewModel.state, .loaded)
    }

    @MainActor
    func testCommentReloadKeepsLoadedCommentsWhenRefreshFails() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let responses = DynamicCommentsResponseSequence([
            .success(#"{"code":0,"data":{"replies":[{"rpid":202}],"top_replies":[],"cursor":{"is_end":true}}}"#),
            .failure(URLError(.notConnectedToInternet)),
        ])
        DynamicCommentsURLProtocol.install { request in
            try responses.nextResponse(for: request)
        }
        defer { DynamicCommentsURLProtocol.reset() }

        let viewModel = DynamicCommentsViewModel(item: try makeCommentableItem(), api: try makeCommentsAPI())
        await viewModel.loadInitial()
        XCTAssertEqual(viewModel.comments.map(\.id), [202])

        await BiliAPIResponseMemoryCache.shared.clear()
        await viewModel.reload()

        XCTAssertEqual(viewModel.comments.map(\.id), [202])
        XCTAssertEqual(viewModel.state, .loaded)
    }

    @MainActor
    func testRegisterSubmittedCommentUpdatesDisplayedReplyCount() throws {
        let viewModel = DynamicCommentsViewModel(item: try makeCommentableItem(), api: try makeCommentsAPI())

        XCTAssertNil(viewModel.displayedReplyCount)
        viewModel.registerSubmittedComment()
        XCTAssertEqual(viewModel.displayedReplyCount, 1)
        viewModel.registerSubmittedComment()
        XCTAssertEqual(viewModel.displayedReplyCount, 2)
    }

    private func decodeOriginal(_ json: String) throws -> DynamicOriginalItem {
        try JSONDecoder.bili.decode(DynamicOriginalItem.self, from: Data(json.utf8))
    }

    private func makeCommentableItem() throws -> DynamicFeedItem {
        try JSONDecoder.bili.decode(
            DynamicFeedItem.self,
            from: Data(
                #"{"id_str":"commentable-dynamic","type":"DYNAMIC_TYPE_WORD","basic":{"comment_id_str":"456","comment_type":17},"modules":{"module_dynamic":{"desc":{"text":"commentable"}}}}"#.utf8
            )
        )
    }

    @MainActor
    private func makeAPI() throws -> BiliAPIClient {
        let service = "DynamicDetailNavigationTests.\(UUID().uuidString)"
        let keychain = KeychainStore(service: service)
        let sessionStore = SessionStore(keychain: keychain)
        let libraryStore = LibraryStore(userDefaults: UserDefaults(suiteName: service)!)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DynamicDetailURLProtocol.self]
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false

        return BiliAPIClient(
            session: URLSession(configuration: configuration),
            sessionStore: sessionStore,
            libraryStore: libraryStore,
            homeRecommendDiagnosticsStore: .shared
        )
    }

    @MainActor
    private func makeCommentsAPI() throws -> BiliAPIClient {
        let service = "DynamicCommentsViewModelTests.\(UUID().uuidString)"
        let keychain = KeychainStore(service: service)
        let sessionStore = SessionStore(keychain: keychain)
        let libraryStore = LibraryStore(userDefaults: UserDefaults(suiteName: service)!)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DynamicCommentsURLProtocol.self]
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false

        return BiliAPIClient(
            session: URLSession(configuration: configuration),
            sessionStore: sessionStore,
            libraryStore: libraryStore,
            homeRecommendDiagnosticsStore: .shared
        )
    }
}

private func dynamicDetailResponse(
    for request: URLRequest,
    body: String
) -> (HTTPURLResponse, Data) {
    let url = request.url ?? URL(string: "https://api.bilibili.com")!
    let response = HTTPURLResponse(
        url: url,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
    )!
    return (response, Data(body.utf8))
}

private final class DynamicDetailRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequest: URLRequest?

    var request: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return storedRequest
    }

    func record(_ request: URLRequest) {
        lock.lock()
        storedRequest = request
        lock.unlock()
    }
}

private final class DynamicDetailURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let state = HandlerState()

    static func install(_ handler: @escaping Handler) {
        state.install(handler)
    }

    static func reset() {
        state.reset()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "api.bilibili.com"
            && request.url?.path == "/x/polymer/web-dynamic/v1/detail"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let result = try Self.currentHandler()(request)
            client?.urlProtocol(self, didReceive: result.0, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: result.1)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func currentHandler() throws -> Handler {
        try state.currentHandler()
    }

    private final class HandlerState: @unchecked Sendable {
        private let lock = NSLock()
        private var handler: Handler?

        func install(_ handler: @escaping Handler) {
            lock.lock()
            self.handler = handler
            lock.unlock()
        }

        func reset() {
            lock.lock()
            handler = nil
            lock.unlock()
        }

        func currentHandler() throws -> Handler {
            lock.lock()
            let handler = self.handler
            lock.unlock()
            guard let handler else {
                throw URLError(.badServerResponse)
            }
            return handler
        }
    }
}

private final class DynamicCommentsResponseSequence: @unchecked Sendable {
    enum Response {
        case success(String)
        case failure(Error)
    }

    private let lock = NSLock()
    private var responses: [Response]

    init(_ responses: [Response]) {
        self.responses = responses
    }

    func nextResponse(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        lock.lock()
        let response = responses.isEmpty ? nil : responses.removeFirst()
        lock.unlock()

        switch response {
        case .success(let body):
            return dynamicDetailResponse(for: request, body: body)
        case .failure(let error):
            throw error
        case nil:
            throw URLError(.badServerResponse)
        }
    }
}

private final class DynamicCommentsURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let state = HandlerState()

    static func install(_ handler: @escaping Handler) {
        state.install(handler)
    }

    static func reset() {
        state.reset()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "api.bilibili.com"
            && request.url?.path == "/x/v2/reply/main"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let result = try Self.currentHandler()(request)
            client?.urlProtocol(self, didReceive: result.0, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: result.1)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func currentHandler() throws -> Handler {
        try state.currentHandler()
    }

    private final class HandlerState: @unchecked Sendable {
        private let lock = NSLock()
        private var handler: Handler?

        func install(_ handler: @escaping Handler) {
            lock.lock()
            self.handler = handler
            lock.unlock()
        }

        func reset() {
            lock.lock()
            handler = nil
            lock.unlock()
        }

        func currentHandler() throws -> Handler {
            lock.lock()
            let handler = self.handler
            lock.unlock()
            guard let handler else {
                throw URLError(.badServerResponse)
            }
            return handler
        }
    }
}
