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

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")

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
}

private final class RequestContractRecorder: @unchecked Sendable {
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
