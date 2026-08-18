import Foundation
import XCTest

@testable import bili

@MainActor
final class BiliAPIClientRequestContractTests: XCTestCase {
    func testSearchSuggestBuildsStableEncodedQueryForwardsHeadersAndDecodes() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "search request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body: """
                    {"code":0,"message":"0","data":{"tag":[{"value":"测试结果","ref":7}]}}
                    """
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let cookieHeader = "SESSDATA=session-value; DedeUserID=1001; buvid3=buvid-value"
        let api = try makeAPI(cookieHeader: cookieHeader)
        let term = "A+B & 中/文"
        let suggestions = try await api.fetchSearchSuggest(term: term)

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(suggestions.map(\.value), ["测试结果"])
        let request = try XCTUnwrap(recorder.request)
        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(url.host, "api.bilibili.com")
        XCTAssertEqual(url.path, "/x/web-interface/search/suggest")
        XCTAssertEqual(
            components.queryItems,
            [
                URLQueryItem(name: "highlight", value: ""),
                URLQueryItem(name: "main_ver", value: "v1"),
                URLQueryItem(name: "term", value: term),
            ]
        )
        XCTAssertEqual(
            components.percentEncodedQuery,
            "highlight=&main_ver=v1&term=A+B%20%26%20%E4%B8%AD/%E6%96%87"
        )
        XCTAssertEqual(
            cookieValues(in: request.value(forHTTPHeaderField: "Cookie")),
            cookieValues(in: cookieHeader)
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://www.bilibili.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "https://www.bilibili.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json, text/plain, */*")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "User-Agent"),
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        )
    }

    func testSearchHotSearchPropagatesAPIErrorResponse() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "search API error captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            if request.url?.path == "/x/web-interface/nav" {
                return Self.response(
                    for: request,
                    body: """
                        {"code":0,"data":{"wbi_img":{"img_url":"https://i.example.com/abc.png","sub_url":"https://i.example.com/def.png"}}}
                        """
                )
            }
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body: """
                    {"code":-352,"message":"风控校验失败","data":null}
                    """
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value")

        do {
            _ = try await api.fetchHotSearch()
            XCTFail("Expected the API error to be propagated")
        } catch let error as BiliAPIError {
            guard case .api(let code, let message) = error else {
                return XCTFail("Unexpected API error: \(error)")
            }
            XCTAssertEqual(code, -352)
            XCTAssertEqual(message, "风控校验失败")
        }

        await fulfillment(of: [requestExpectation], timeout: 2)
        XCTAssertEqual(recorder.request?.url?.path, "/x/web-interface/wbi/search/square")
    }

    func testMainCommentsBuildsRequestAndDecodesPaginationAndComments() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "main comments request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body: """
                    {"code":0,"data":{"replies":[{"rpid":12345}],"top_replies":[],"cursor":{"next":"next-cursor","is_end":false}}}
                    """
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value")
        let cursor = "cursor/with+symbols"
        let page = try await api.fetchComments(oid: "456", type: 11, cursor: cursor, sort: .hot)

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(page.replies?.map(\.id), [12345])
        let request = try XCTUnwrap(recorder.request)
        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(url.path, "/x/v2/reply/main")
        var query = queryValues(in: components)
        let pagination = try XCTUnwrap(query.removeValue(forKey: "pagination_str"))
        let paginationObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(pagination.utf8)) as? [String: String]
        )
        XCTAssertEqual(paginationObject, ["offset": cursor])
        XCTAssertEqual(
            query,
            [
                "oid": "456",
                "type": "11",
                "mode": "3",
                "plat": "1",
            ]
        )
    }

    func testCommentRepliesBuildsPagingAndTimeSortRequestAndDecodes() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "comment replies request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body: """
                    {"code":0,"data":{"replies":[{"rpid":67890}],"top_replies":[]}}
                    """
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        let page = try await api.fetchCommentReplies(
            oid: "456",
            type: 11,
            root: 987,
            page: 3,
            sort: .time
        )

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(page.replies?.map(\.id), [67890])
        let request = try XCTUnwrap(recorder.request)
        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(url.path, "/x/v2/reply/reply")
        XCTAssertEqual(
            queryValues(in: components),
            [
                "oid": "456",
                "type": "11",
                "root": "987",
                "pn": "3",
                "ps": "20",
                "sort": "1",
            ]
        )
    }

    func testCommentDialogBuildsRequestAndDecodesResponse() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "comment dialog request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body: """
                    {"code":0,"data":{"replies":[{"rpid":24680}],"top_replies":[]}}
                    """
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value")
        let page = try await api.fetchCommentDialog(oid: "321", type: 1, root: 654, dialog: 987, size: 12)

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(page.replies?.map(\.id), [24680])
        let request = try XCTUnwrap(recorder.request)
        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(url.path, "/x/v2/reply/dialog/cursor")
        XCTAssertEqual(
            queryValues(in: components),
            [
                "oid": "321",
                "type": "1",
                "root": "654",
                "dialog": "987",
                "size": "12",
            ]
        )
    }

    func testCommentDialogPropagatesAPIError() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "comment dialog error captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body: """
                    {"code":-404,"message":"评论不存在","data":null}
                    """
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value")
        do {
            _ = try await api.fetchCommentDialog(oid: "999", type: 1, root: 1000, dialog: 1001)
            XCTFail("Expected the API error to be propagated")
        } catch let error as BiliAPIError {
            guard case .api(let code, let message) = error else {
                return XCTFail("Unexpected API error: \(error)")
            }
            XCTAssertEqual(code, -404)
            XCTAssertEqual(message, "评论不存在")
        }

        await fulfillment(of: [requestExpectation], timeout: 2)
        XCTAssertEqual(recorder.request?.url?.path, "/x/v2/reply/dialog/cursor")
    }

    func testDynamicFeedBuildsFirstPageAndOffsetPaginationRequests() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "dynamic feed requests captured")
        requestExpectation.expectedFulfillmentCount = 2
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            guard request.url?.path == "/x/polymer/web-dynamic/v1/feed/all" else {
                throw URLError(.badServerResponse)
            }
            requestExpectation.fulfill()
            let offset = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "offset" })?
                .value
            let responseOffset = offset == nil ? "next-offset" : "final-offset"
            let hasMore = offset == nil ? "true" : "false"
            return Self.response(
                for: request,
                body: """
                    {"code":0,"data":{"items":[],"has_more":\(hasMore),"offset":"\(responseOffset)"}}
                    """
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        let firstPage = try await api.fetchDynamicFeed()
        let nextPage = try await api.fetchDynamicFeed(offset: "next-offset")

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(firstPage.offset, "next-offset")
        XCTAssertEqual(nextPage.offset, "final-offset")
        let requests = recorder.requests
        XCTAssertEqual(requests.count, 2)
        for request in requests {
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(url.path, "/x/polymer/web-dynamic/v1/feed/all")
            let cookies = cookieValues(in: request.value(forHTTPHeaderField: "Cookie"))
            XCTAssertEqual(cookies["SESSDATA"], "session-value")
            XCTAssertEqual(cookies["DedeUserID"], "1001")
        }
        let firstRequest = try XCTUnwrap(
            requests.first(where: {
                guard let components = URLComponents(url: $0.url!, resolvingAgainstBaseURL: false) else {
                    return false
                }
                return queryValues(in: components)["offset"] == nil
            })
        )
        let firstQuery = try XCTUnwrap(URLComponents(url: firstRequest.url!, resolvingAgainstBaseURL: false))
        XCTAssertEqual(
            queryValues(in: firstQuery),
            [
                "features":
                    "itemOpusStyle,listOnlyfans,opusBigCover,onlyfansVote,decorationCard,onlyfansAssetsV2,forwardListHidden,ugcDelete",
                "platform": "web",
                "type": "all",
                "web_location": "333.1365",
            ]
        )
        let secondRequest = try XCTUnwrap(
            requests.first(where: {
                guard let components = URLComponents(url: $0.url!, resolvingAgainstBaseURL: false) else {
                    return false
                }
                return queryValues(in: components)["offset"] == "next-offset"
            })
        )
        let secondQuery = try XCTUnwrap(URLComponents(url: secondRequest.url!, resolvingAgainstBaseURL: false))
        XCTAssertEqual(queryValues(in: secondQuery)["offset"], "next-offset")
    }

    func testDynamicPortalBuildsRequestAndDecodes() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "dynamic portal request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body: """
                    {"code":0,"data":{}}
                    """
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        _ = try await api.fetchDynamicPortal()

        await fulfillment(of: [requestExpectation], timeout: 2)

        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.url?.path, "/x/polymer/web-dynamic/v1/portal")
        let components = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
        XCTAssertEqual(
            queryValues(in: components),
            ["up_list_more": "1", "web_location": "333.1365"]
        )
        XCTAssertEqual(cookieValues(in: request.value(forHTTPHeaderField: "Cookie"))["SESSDATA"], "session-value")
    }

    func testUploaderDynamicFeedBuildsSignedRequestWithAuthenticatedCookie() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "uploader dynamic requests captured")
        requestExpectation.expectedFulfillmentCount = 2
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            if request.url?.path == "/x/web-interface/nav" {
                requestExpectation.fulfill()
                return Self.response(
                    for: request,
                    body: """
                        {"code":0,"data":{"wbi_img":{"img_url":"https://i0.hdslb.com/bfs/wbi/abcdef.png","sub_url":"https://i0.hdslb.com/bfs/wbi/ghijkl.png"}}}
                        """
                )
            }
            guard request.url?.path == "/x/polymer/web-dynamic/v1/feed/space" else {
                throw URLError(.badServerResponse)
            }
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body: """
                    {"code":0,"data":{"items":[],"has_more":false,"offset":"space-offset"}}
                    """
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let cookieHeader = "SESSDATA=session-value; DedeUserID=1001"
        let api = try makeAPI(cookieHeader: cookieHeader)
        _ = try await api.refreshPlaybackSigningKeys()
        let page = try await api.fetchUploaderDynamicFeed(mid: 2002, offset: "space-cursor")

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(page.offset, "space-offset")
        let requests = recorder.requests
        XCTAssertEqual(requests.count, 2)
        let uploaderRequest = try XCTUnwrap(requests.last)
        XCTAssertEqual(uploaderRequest.url?.path, "/x/polymer/web-dynamic/v1/feed/space")
        let components = try XCTUnwrap(URLComponents(url: uploaderRequest.url!, resolvingAgainstBaseURL: false))
        let query = queryValues(in: components)
        XCTAssertEqual(query["host_mid"], "2002")
        XCTAssertEqual(query["offset"], "space-cursor")
        XCTAssertEqual(query["platform"], "web")
        XCTAssertEqual(query["web_location"], "333.1387")
        XCTAssertNotNil(query["w_rid"])
        XCTAssertNotNil(query["wts"])
        XCTAssertEqual(uploaderRequest.value(forHTTPHeaderField: "Referer"), "https://space.bilibili.com/2002/dynamic")
        XCTAssertEqual(uploaderRequest.value(forHTTPHeaderField: "Origin"), "https://space.bilibili.com")
        XCTAssertEqual(
            uploaderRequest.value(forHTTPHeaderField: "User-Agent"),
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.2 Safari/605.1.15"
        )
        let uploaderCookies = cookieValues(in: uploaderRequest.value(forHTTPHeaderField: "Cookie"))
        XCTAssertEqual(uploaderCookies["SESSDATA"], "session-value")
        XCTAssertEqual(uploaderCookies["DedeUserID"], "1001")
    }

    func testDynamicFeedPropagatesAPIError() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "dynamic feed error captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body: """
                    {"code":-352,"message":"风控校验失败","data":null}
                    """
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        do {
            _ = try await api.fetchDynamicFeed(offset: "error-offset")
            XCTFail("Expected the dynamic feed API error to be propagated")
        } catch let error as BiliAPIError {
            guard case .api(let code, let message) = error else {
                return XCTFail("Unexpected API error: \(error)")
            }
            XCTAssertEqual(code, -352)
            XCTAssertEqual(message, "风控校验失败")
        }

        await fulfillment(of: [requestExpectation], timeout: 2)
        XCTAssertEqual(recorder.request?.url?.path, "/x/polymer/web-dynamic/v1/feed/all")
    }

    private func makeAPI(cookieHeader: String) throws -> BiliAPIClient {
        let keychainService = "BiliAPIClientRequestContractTests.\(UUID().uuidString)"
        let keychain = KeychainStore(service: keychainService)
        let cookieValues = cookieHeader.split(separator: ";").reduce(into: [String: String]()) { values, item in
            let parts = item.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { return }
            values[String(parts[0]).trimmingCharacters(in: .whitespaces)] = String(parts[1]).trimmingCharacters(
                in: .whitespaces)
        }
        try keychain.save(cookieHeader, for: "LOGIN_COOKIE_HEADER")
        try keychain.save(cookieValues["SESSDATA"] ?? "", for: "SESSDATA")
        try keychain.save(LoginCredentialKind.web.rawValue, for: "LOGIN_CREDENTIAL_KIND")

        let sessionStore = SessionStore(keychain: keychain)
        if cookieValues["DedeUserID"] != nil {
            try sessionStore.saveLoginCookies(cookieValues, credentialKind: .web)
        }
        let libraryStore = LibraryStore(userDefaults: UserDefaults(suiteName: keychainService)!)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RequestContractURLProtocol.self]
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration)
        return BiliAPIClient(
            session: session,
            sessionStore: sessionStore,
            libraryStore: libraryStore,
            homeRecommendDiagnosticsStore: .shared
        )
    }

    private static func response(for request: URLRequest, body: String) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(body.utf8))
    }

    private func cookieValues(in header: String?) -> [String: String] {
        (header ?? "").split(separator: ";").reduce(into: [:]) { values, item in
            let pair = item.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else { return }
            values[String(pair[0]).trimmingCharacters(in: .whitespaces)] = String(pair[1])
                .trimmingCharacters(in: .whitespaces)
        }
    }

    private func queryValues(in components: URLComponents) -> [String: String] {
        components.queryItems?.reduce(into: [:]) { values, item in
            values[item.name] = item.value ?? ""
        } ?? [:]
    }
}

private final class RequestContractRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequests: [URLRequest] = []

    var request: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests.last
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests
    }

    func record(_ request: URLRequest) {
        lock.lock()
        storedRequests.append(request)
        lock.unlock()
    }
}

private final class RequestContractURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    private static var handler: Handler?

    static func install(_ handler: @escaping Handler) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        handler = nil
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "api.bilibili.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let result: (HTTPURLResponse, Data) = try Self.currentHandler()(request)
            client?.urlProtocol(self, didReceive: result.0, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: result.1)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func currentHandler() throws -> Handler {
        lock.lock()
        let handler = self.handler
        lock.unlock()
        guard let handler else {
            throw URLError(.badServerResponse)
        }
        return handler
    }
}
