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

    func testAccountHistoryBuildsFirstPageAndCursorPaginationRequests() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "account history requests captured")
        requestExpectation.expectedFulfillmentCount = 2
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            let query = self.queryValues(for: request)
            if query["max"] == "0" {
                return Self.response(
                    for: request,
                    body: """
                        {"code":0,"data":{"list":[{"bvid":"BVfirst","aid":101,"title":"第一条","view_at":1700000000}]}}
                        """
                )
            }
            return Self.response(
                for: request,
                body: """
                    {"code":0,"data":{"list":[{"bvid":"BVsecond","aid":100,"title":"第二条","view_at":1699999000}]}}
                    """
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        let entries = try await api.fetchAccountHistory(page: 2, pageSize: 1)

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(entries.map(\.bvid), ["BVsecond"])
        XCTAssertEqual(recorder.requests.count, 2)
        let firstQuery = try XCTUnwrap(
            URLComponents(url: try XCTUnwrap(recorder.requests[0].url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(
            queryValues(in: firstQuery),
            [
                "type": "archive",
                "ps": "1",
                "max": "0",
                "view_at": "0",
            ])
        let secondQuery = try XCTUnwrap(
            URLComponents(url: try XCTUnwrap(recorder.requests[1].url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(
            queryValues(in: secondQuery),
            [
                "type": "archive",
                "ps": "1",
                "max": "101",
                "view_at": "1700000000",
            ])
        XCTAssertEqual(
            cookieValues(in: recorder.requests[0].value(forHTTPHeaderField: "Cookie"))["SESSDATA"], "session-value")
    }

    func testAccountFavoritesBuildFolderListAndDeduplicateAcrossFolders() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "account favorite requests captured")
        requestExpectation.expectedFulfillmentCount = 3
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            switch request.url?.path {
            case "/x/v3/fav/folder/created/list-all":
                return Self.response(
                    for: request,
                    body: """
                        {"code":0,"data":{"list":[{"id":7},{"id":8}]}}
                        """
                )
            case "/x/v3/fav/resource/list":
                let folderID = self.queryValues(for: request)["media_id"]
                let body =
                    folderID == "7"
                    ? """
                    {"code":0,"data":{"medias":[{"bvid":"BVone","aid":1},{"bvid":"BVtwo","aid":2}]}}
                    """
                    : """
                    {"code":0,"data":{"medias":[{"bvid":"BVtwo","aid":2},{"bvid":"BVthree","aid":3}]}}
                    """
                return Self.response(for: request, body: body)
            default:
                throw URLError(.badServerResponse)
            }
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        let entries = try await api.fetchAccountFavorites(page: 2, pageSize: 3)

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(entries.map(\.bvid), ["BVone", "BVtwo", "BVthree"])
        XCTAssertEqual(recorder.requests.count, 3)
        let folderQuery = try XCTUnwrap(
            URLComponents(url: try XCTUnwrap(recorder.requests[0].url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(queryValues(in: folderQuery), ["up_mid": "1001", "type": "2"])
        let firstFolderQuery = try XCTUnwrap(
            URLComponents(url: try XCTUnwrap(recorder.requests[1].url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(
            queryValues(in: firstFolderQuery),
            [
                "media_id": "7",
                "pn": "2",
                "ps": "3",
                "keyword": "",
                "order": "mtime",
                "type": "0",
                "tid": "0",
                "platform": "web",
            ])
        let favoriteCookieValues = cookieValues(in: recorder.requests[1].value(forHTTPHeaderField: "Cookie"))
        XCTAssertEqual(favoriteCookieValues["SESSDATA"], "session-value")
        XCTAssertEqual(favoriteCookieValues["DedeUserID"], "1001")
    }

    func testAccountFavoritesReturnsSuccessfulEntriesWhenAnotherFolderFails() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "partial favorite requests captured")
        requestExpectation.expectedFulfillmentCount = 3
        RequestContractURLProtocol.install { request in
            requestExpectation.fulfill()
            switch request.url?.path {
            case "/x/v3/fav/folder/created/list-all":
                return Self.response(
                    for: request,
                    body: """
                        {"code":0,"data":{"list":[{"id":7},{"id":8}]}}
                        """
                )
            case "/x/v3/fav/resource/list":
                let folderID = self.queryValues(for: request)["media_id"]
                if folderID == "7" {
                    return Self.response(
                        for: request,
                        body: "{\"code\":-500,\"message\":\"临时失败\",\"data\":null}"
                    )
                }
                return Self.response(
                    for: request,
                    body: """
                        {"code":0,"data":{"medias":[{"bvid":"BVsuccess","aid":3}]}}
                        """
                )
            default:
                throw URLError(.badServerResponse)
            }
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        let entries = try await api.fetchAccountFavorites(pageSize: 20)

        await fulfillment(of: [requestExpectation], timeout: 2)
        XCTAssertEqual(entries.map(\.bvid), ["BVsuccess"])
    }

    func testFavoriteFolderPagePropagatesAPIErrorAndBuildsRequest() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "favorite folder error captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body: """
                    {"code":-404,"message":"收藏夹不存在","data":null}
                    """
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        do {
            _ = try await api.fetchFavoriteFolderVideoPage(folderID: 12, page: 3, pageSize: 15)
            XCTFail("Expected the favorite folder API error to be propagated")
        } catch let error as BiliAPIError {
            guard case .api(let code, let message) = error else {
                return XCTFail("Unexpected API error: \(error)")
            }
            XCTAssertEqual(code, -404)
            XCTAssertEqual(message, "收藏夹不存在")
        }

        await fulfillment(of: [requestExpectation], timeout: 2)
        let request = try XCTUnwrap(recorder.request)
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(queryValues(in: components)["media_id"], "12")
        XCTAssertEqual(queryValues(in: components)["pn"], "3")
        XCTAssertEqual(queryValues(in: components)["ps"], "15")
    }

    func testAccountHistoryRequiresAuthenticatedHistoryAccount() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            throw URLError(.badServerResponse)
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "")
        do {
            _ = try await api.fetchAccountHistoryPage(pageSize: 20)
            XCTFail("Expected account history authentication to be required")
        } catch let error as BiliAPIError {
            guard case .missingSESSDATA = error else {
                return XCTFail("Unexpected API error: \(error)")
            }
        }
        XCTAssertTrue(recorder.requests.isEmpty)
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

    func testVideoInteractionStateBuildsRelationRequestAndDecodes() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "video relation request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body: """
                    {"code":0,"data":{"like":1,"coin":2,"favorite":1,"attention":1}}
                    """
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        let state = try await api.fetchVideoInteractionState(aid: 123, bvid: "BV1test")

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertTrue(state.isLiked)
        XCTAssertEqual(state.coinCount, 2)
        XCTAssertTrue(state.isFavorited)
        XCTAssertFalse(state.isFollowing)
        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.url?.path, "/x/web-interface/archive/relation")
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(queryValues(in: components), ["aid": "123", "bvid": "BV1test"])
    }

    func testVideoLikeBuildsCSRFFormAndRetriesIdempotently() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "like requests captured")
        requestExpectation.expectedFulfillmentCount = 2
        let recorder = RequestContractRecorder()
        let attemptLock = NSLock()
        var attempts = 0
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            attemptLock.lock()
            attempts += 1
            let currentAttempt = attempts
            attemptLock.unlock()
            if currentAttempt == 1 {
                throw URLError(.timedOut)
            }
            return Self.response(for: request, body: "{\"code\":0,\"data\":{}}")
        }
        defer { RequestContractURLProtocol.reset() }

        let cookieHeader = "SESSDATA=session-value; bili_jct=csrf-value; DedeUserID=1001"
        let api = try makeAPI(cookieHeader: cookieHeader)
        try await api.toggleVideoLike(aid: 456, liked: true)

        await fulfillment(of: [requestExpectation], timeout: 3)

        XCTAssertEqual(recorder.requests.count, 2)
        for request in recorder.requests {
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/x/web-interface/archive/like")
            XCTAssertEqual(
                formValues(in: request),
                [
                    "aid": "456",
                    "like": "1",
                    "csrf": "csrf-value",
                    "cross_domain": "true",
                    "source": "web_normal",
                    "ga": "1",
                ])
            XCTAssertEqual(cookieValues(in: request.value(forHTTPHeaderField: "Cookie"))["SESSDATA"], "session-value")
            XCTAssertEqual(cookieValues(in: request.value(forHTTPHeaderField: "Cookie"))["bili_jct"], "csrf-value")
        }
    }

    func testVideoCoinValidatesMultiplyAndBuildsForm() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "coin request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(for: request, body: "{\"code\":0,\"data\":{}}")
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; bili_jct=csrf-value; DedeUserID=1001")
        do {
            try await api.addVideoCoin(aid: 789, multiply: 3)
            XCTFail("Expected invalid coin quantity to fail")
        } catch let error as BiliAPIError {
            guard case .api(let code, let message) = error else {
                return XCTFail("Unexpected API error: \(error)")
            }
            XCTAssertEqual(code, -1)
            XCTAssertEqual(message, "投币数量无效")
        }
        XCTAssertTrue(recorder.requests.isEmpty)

        try await api.addVideoCoin(aid: 789, multiply: 2, selectLike: true)
        await fulfillment(of: [requestExpectation], timeout: 2)

        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.url?.path, "/x/web-interface/coin/add")
        XCTAssertEqual(
            formValues(in: request),
            [
                "aid": "789",
                "multiply": "2",
                "select_like": "1",
                "csrf": "csrf-value",
                "cross_domain": "true",
                "source": "web_normal",
                "ga": "1",
            ])
    }

    func testFavoriteFoldersAndMutationBuildExpectedRequests() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "favorite requests captured")
        requestExpectation.expectedFulfillmentCount = 4
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            if request.url?.path == "/x/v3/fav/folder/created/list-all" {
                return Self.response(
                    for: request,
                    body: "{\"code\":0,\"data\":{\"list\":[{\"id\":7,\"title\":\"默认收藏夹\"}]}}"
                )
            }
            return Self.response(for: request, body: "{\"code\":0,\"data\":{}}")
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; bili_jct=csrf-value; DedeUserID=1001")
        let folders = try await api.fetchFavoriteFolders(for: 321)
        try await api.setVideoFavorite(aid: 321, favorited: true)
        try await api.setVideoFavorite(aid: 321, addFolderIDs: [9, 7], removeFolderIDs: [11, 7])

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(folders.map(\.id), [7])
        let requests = recorder.requests
        XCTAssertEqual(requests.count, 4)
        XCTAssertEqual(requests[0].url?.path, "/x/v3/fav/folder/created/list-all")
        let folderQuery = try XCTUnwrap(
            URLComponents(url: try XCTUnwrap(requests[0].url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(queryValues(in: folderQuery), ["up_mid": "1001", "type": "2", "rid": "321"])
        XCTAssertEqual(requests[1].url?.path, "/x/v3/fav/folder/created/list-all")
        let repeatedFolderQuery = try XCTUnwrap(
            URLComponents(url: try XCTUnwrap(requests[1].url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(queryValues(in: repeatedFolderQuery), ["up_mid": "1001", "type": "2", "rid": "321"])
        XCTAssertEqual(
            formValues(in: requests[2]),
            [
                "rid": "321",
                "type": "2",
                "add_media_ids": "7",
                "del_media_ids": "",
                "csrf": "csrf-value",
                "platform": "web",
                "gaia_source": "web_normal",
                "ga": "1",
            ])
        XCTAssertEqual(
            formValues(in: requests[3]),
            [
                "rid": "321",
                "type": "2",
                "add_media_ids": "9",
                "del_media_ids": "11",
                "csrf": "csrf-value",
                "platform": "web",
                "gaia_source": "web_normal",
                "ga": "1",
            ])
    }

    func testUploaderFollowWebMutationBuildsFormAndPropagatesAPIError() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "follow request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body: "{\"code\":-400,\"message\":\"关注失败\",\"data\":null}"
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; bili_jct=csrf-value; DedeUserID=1001")
        do {
            try await api.setUploaderFollowing(mid: 654, following: true)
            XCTFail("Expected follow API error")
        } catch let error as BiliAPIError {
            guard case .api(let code, let message) = error else {
                return XCTFail("Unexpected API error: \(error)")
            }
            XCTAssertEqual(code, -400)
            XCTAssertEqual(message, "关注失败")
        }

        await fulfillment(of: [requestExpectation], timeout: 2)
        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.url?.path, "/x/relation/modify")
        XCTAssertEqual(
            formValues(in: request),
            [
                "fid": "654",
                "act": "1",
                "re_src": "11",
                "csrf": "csrf-value",
                "gaia_source": "web_normal",
                "ga": "1",
            ])
    }

    func testUploaderProfileRejectsInvalidMIDWithoutRequest() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            throw URLError(.badServerResponse)
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        for operation in [
            { try await api.fetchUploaderProfile(mid: 0) },
            { try await api.fetchUploaderStatsProfile(mid: -1) },
        ] {
            do {
                _ = try await operation()
                XCTFail("Expected invalid uploader UID to fail")
            } catch let error as BiliAPIError {
                guard case .api(let code, let message) = error else {
                    return XCTFail("Unexpected API error: \(error)")
                }
                XCTAssertEqual(code, -1)
                XCTAssertEqual(message, "UP 主 UID 无效")
            }
        }
        XCTAssertTrue(recorder.requests.isEmpty)
    }

    func testUploaderProfileMergesVisibleSourcesAndSurvivesPartialFailures() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            let query = self.queryValues(for: request)
            switch (request.url?.host, request.url?.path) {
            case ("api.bilibili.com", "/x/web-interface/card"):
                return Self.response(
                    for: request,
                    body: "{\"code\":-500,\"message\":\"card failed\",\"data\":null}"
                )
            case ("app.bilibili.com", "/x/v2/space"):
                return Self.response(
                    for: request,
                    body: "{\"code\":0,\"data\":{\"card\":{\"mid\":123,\"name\":\"测试UP\",\"fans\":200}}}"
                )
            case ("api.bilibili.com", "/x/web-interface/nav"):
                return Self.response(
                    for: request,
                    body: "{\"code\":0,\"data\":{\"wbi_img\":{"
                        + "\"img_url\":\"https://i0.hdslb.com/bfs/wbi/abcdef.png\","
                        + "\"sub_url\":\"https://i0.hdslb.com/bfs/wbi/ghijkl.png\"}}}"
                )
            case ("api.bilibili.com", "/x/space/wbi/acc/info"):
                return Self.response(
                    for: request,
                    body: "{\"code\":0,\"data\":{\"follower\":300}}"
                )
            case ("api.bilibili.com", "/x/relation/stat"):
                return Self.response(
                    for: request,
                    body: "{\"code\":0,\"data\":{\"following\":12,\"follower\":400}}"
                )
            case ("api.bilibili.com", "/x/space/upstat"):
                return Self.response(
                    for: request,
                    body: "{\"code\":0,\"data\":{\"likes\":999,\"archive\":{\"count\":88}}}"
                )
            case ("api.bilibili.com", "/x/relation"):
                XCTAssertEqual(query["fid"], "123")
                return Self.response(for: request, body: "{\"code\":0,\"data\":{\"attribute\":2}}")
            case ("space.bilibili.com", "/123"):
                return Self.response(
                    for: request,
                    body: "window.__INITIAL_STATE__={\"card\":{\"mid\":123,\"fans\":500}};"
                )
            default:
                throw URLError(.badServerResponse)
            }
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        let profile = try await api.fetchUploaderProfile(mid: 123)

        XCTAssertEqual(profile.card?.name, "测试UP")
        XCTAssertEqual(profile.visibleFollowerCount, 400)
        XCTAssertEqual(profile.visibleFollowingCount, 12)
        XCTAssertEqual(profile.visibleLikeCount, 999)
        XCTAssertEqual(profile.visibleArchiveCount, 88)
        XCTAssertTrue(recorder.requests.contains { $0.url?.path == "/x/web-interface/card" })
        XCTAssertTrue(recorder.requests.contains { $0.url?.path == "/x/v2/space" })
    }

    func testUploaderProfileFallsBackToAppAccessKeyForViewerRelation() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            switch (request.url?.host, request.url?.path) {
            case ("api.bilibili.com", "/x/web-interface/card"):
                return Self.response(
                    for: request,
                    body: "{\"code\":0,\"data\":{\"card\":{\"mid\":123,\"name\":\"测试UP\"}}}"
                )
            case ("app.bilibili.com", "/x/v2/space"):
                return Self.response(
                    for: request,
                    body: "{\"code\":0,\"data\":{\"card\":{\"mid\":123,\"name\":\"测试UP\"}}}"
                )
            case ("api.bilibili.com", "/x/relation"):
                let query = self.queryValues(for: request)
                if query["access_key"] == "app-access-key" {
                    return Self.response(for: request, body: "{\"code\":0,\"data\":{\"attribute\":2}}")
                }
                return Self.response(
                    for: request,
                    body: "{\"code\":-101,\"message\":\"cookie failed\",\"data\":null}"
                )
            default:
                return Self.response(for: request, body: "{\"code\":0,\"data\":null}")
            }
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001",
            accessKey: "app-access-key"
        )
        let profile = try await api.fetchUploaderProfile(mid: 123)

        XCTAssertEqual(profile.following, true)
        let relationRequests = recorder.requests.filter { $0.url?.path == "/x/relation" }
        XCTAssertTrue(relationRequests.contains { self.queryValues(for: $0)["access_key"] == nil })
        XCTAssertTrue(relationRequests.contains { self.queryValues(for: $0)["access_key"] == "app-access-key" })
    }

    func testUploaderWebVideoPageBuildsSignedRequestAndDecodesPagination() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            switch request.url?.path {
            case "/x/web-interface/nav":
                return Self.response(
                    for: request,
                    body: """
                        {"code":0,"data":{"wbi_img":{"img_url":"https://i0.hdslb.com/bfs/wbi/abcdef.png","sub_url":"https://i0.hdslb.com/bfs/wbi/ghijkl.png"}}}
                        """
                )
            case "/x/space/wbi/arc/search":
                return Self.response(
                    for: request,
                    body: """
                        {"code":0,"data":{"list":{"vlist":[{"bvid":"BV1test123","aid":101,"author":"测试UP","mid":321,"title":"测试投稿","length":"01:02"}]},"page":{"count":61}}}
                        """
                )
            default:
                throw URLError(.badServerResponse)
            }
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        let result = try await api.fetchUploaderVideoPage(mid: 321, page: 2, order: .pubdate)

        XCTAssertEqual(result.videos.map(\.bvid), ["BV1test123"])
        XCTAssertEqual(result.totalCount, 61)
        XCTAssertTrue(result.hasMore)
        XCTAssertEqual(result.nextCursor, UploaderVideoPageCursor(aid: "101", next: nil))

        let request = try XCTUnwrap(recorder.requests.last)
        XCTAssertEqual(request.url?.path, "/x/space/wbi/arc/search")
        let query = queryValues(for: request)
        XCTAssertEqual(query["mid"], "321")
        XCTAssertEqual(query["pn"], "2")
        XCTAssertEqual(query["ps"], "30")
        XCTAssertEqual(query["order"], UploaderVideoOrder.pubdate.rawValue)
        XCTAssertEqual(query["platform"], "web")
        XCTAssertEqual(query["web_location"], "333.1387")
        XCTAssertEqual(query["order_avoided"], "true")
        XCTAssertNotNil(query["wts"])
        XCTAssertNotNil(query["w_rid"])
    }

    func testUploaderVideoPageFallsBackToSignedAppArchiveWithCursor() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            switch request.url?.path {
            case "/x/web-interface/nav":
                return Self.response(
                    for: request,
                    body: """
                        {"code":0,"data":{"wbi_img":{"img_url":"https://i0.hdslb.com/bfs/wbi/abcdef.png","sub_url":"https://i0.hdslb.com/bfs/wbi/ghijkl.png"}}}
                        """
                )
            case "/x/space/wbi/arc/search":
                return Self.response(for: request, body: "{\"code\":-352,\"message\":\"web failed\",\"data\":null}")
            case "/x/v2/space/archive/cursor":
                return Self.response(
                    for: request,
                    body: """
                        {"code":0,"data":{"count":42,"has_next":true,"next":77,"item":[{"bvid":"BV1fallback","param":"456","title":"App 投稿","author":"测试UP"}]}}
                        """
                )
            default:
                throw URLError(.badServerResponse)
            }
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        let result = try await api.fetchUploaderVideoPage(
            mid: 321,
            cursor: UploaderVideoPageCursor(aid: "123", next: 45),
            order: .click
        )

        XCTAssertEqual(result.videos.map(\.bvid), ["BV1fallback"])
        XCTAssertEqual(result.totalCount, 42)
        XCTAssertTrue(result.hasMore)
        XCTAssertEqual(result.nextCursor, UploaderVideoPageCursor(aid: "456", next: 77))

        let appRequest = try XCTUnwrap(
            recorder.requests.first { $0.url?.path == "/x/v2/space/archive/cursor" }
        )
        let query = queryValues(for: appRequest)
        XCTAssertEqual(appRequest.url?.host, "app.bilibili.com")
        XCTAssertEqual(query["vmid"], "321")
        XCTAssertEqual(query["aid"], "123")
        XCTAssertEqual(query["next"], "45")
        XCTAssertEqual(query["order"], UploaderVideoOrder.click.rawValue)
        XCTAssertNotNil(query["appkey"])
        XCTAssertNotNil(query["ts"])
        XCTAssertNotNil(query["sign"])
    }

    func testUploaderSeasonSeriesBuildsRequestAndDecodesItems() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            return Self.response(
                for: request,
                body: """
                    {"code":0,"data":{"items_lists":{"page":{"page_num":2,"page_size":5,"total":9},"seasons_list":[{"meta":{"season_id":11,"name":"测试合集"}}],"series_list":[{"meta":{"series_id":12,"name":"测试列表"}}]}}}
                    """
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "")
        let result = try await api.fetchUploaderSeasonSeries(mid: 321, page: 2, pageSize: 5)

        XCTAssertEqual(result.page?.total, 9)
        XCTAssertEqual(result.items.map(\.title), ["测试合集", "测试列表"])
        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.url?.path, "/x/polymer/web-space/seasons_series_list")
        XCTAssertEqual(
            queryValues(for: request),
            ["mid": "321", "page_num": "2", "page_size": "5"]
        )
    }

    func testUploaderSeasonAndSeriesArchivePagesPreservePathsSortAndPagination() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            switch request.url?.path {
            case "/x/polymer/web-space/seasons_archives_list":
                return Self.response(
                    for: request,
                    body: """
                        {"code":0,"data":{"archives":[{"aid":101,"bvid":"BV1season","title":"合集投稿"}],"page":{"page_num":2,"page_size":30,"total":61}}}
                        """
                )
            case "/x/series/archives":
                return Self.response(
                    for: request,
                    body: """
                        {"code":0,"data":{"archives":[{"aid":102,"bvid":"BV1series","title":"列表投稿"}],"page":{"page_num":2,"page_size":20,"total":40}}}
                        """
                )
            default:
                throw URLError(.badServerResponse)
            }
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "")
        let owner = VideoOwner(mid: 321, name: "测试UP", face: nil)
        let season = try await api.fetchUploaderSeasonSeriesArchivePage(
            mid: 321,
            owner: owner,
            kind: .season(11),
            page: 2,
            pageSize: 30,
            sort: .asc
        )
        let series = try await api.fetchUploaderSeasonSeriesArchivePage(
            mid: 321,
            owner: owner,
            kind: .series(12),
            page: 2,
            pageSize: 20,
            sort: .desc
        )

        XCTAssertEqual(season.videos.map(\.bvid), ["BV1season"])
        XCTAssertEqual(season.totalCount, 61)
        XCTAssertTrue(season.hasMore)
        XCTAssertEqual(series.videos.map(\.bvid), ["BV1series"])
        XCTAssertEqual(series.totalCount, 40)
        XCTAssertFalse(series.hasMore)

        let seasonRequest = try XCTUnwrap(
            recorder.requests.first { $0.url?.path == "/x/polymer/web-space/seasons_archives_list" }
        )
        XCTAssertEqual(
            queryValues(for: seasonRequest),
            [
                "mid": "321",
                "season_id": "11",
                "sort_reverse": "true",
                "page_size": "30",
                "page_num": "2",
                "web_location": "333.1387",
            ]
        )
        let seriesRequest = try XCTUnwrap(
            recorder.requests.first { $0.url?.path == "/x/series/archives" }
        )
        XCTAssertEqual(
            queryValues(for: seriesRequest),
            [
                "mid": "321",
                "series_id": "12",
                "sort": "desc",
                "ps": "20",
                "pn": "2",
                "web_location": "333.1387",
            ]
        )
    }

    func testUploaderSeasonSeriesRejectsInvalidMIDAndMissingPayload() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            return Self.response(for: request, body: "{\"code\":0,\"data\":null}")
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "")
        let owner = VideoOwner(mid: 321, name: "测试UP", face: nil)
        do {
            _ = try await api.fetchUploaderSeasonSeries(mid: 0)
            XCTFail("Expected invalid uploader UID to fail")
        } catch let error as BiliAPIError {
            guard case .api(let code, let message) = error else {
                return XCTFail("Unexpected API error: \(error)")
            }
            XCTAssertEqual(code, -1)
            XCTAssertEqual(message, "UP 主 UID 无效")
        }
        do {
            _ = try await api.fetchUploaderSeasonSeriesArchivePage(
                mid: -1,
                owner: owner,
                kind: .season(11)
            )
            XCTFail("Expected invalid uploader UID to fail")
        } catch let error as BiliAPIError {
            guard case .api(let code, let message) = error else {
                return XCTFail("Unexpected API error: \(error)")
            }
            XCTAssertEqual(code, -1)
            XCTAssertEqual(message, "UP 主 UID 无效")
        }
        XCTAssertTrue(recorder.requests.isEmpty)

        do {
            _ = try await api.fetchUploaderSeasonSeries(mid: 321)
            XCTFail("Expected missing payload to fail")
        } catch let error as BiliAPIError {
            guard case .missingPayload = error else {
                return XCTFail("Unexpected API error: \(error)")
            }
        }
        XCTAssertEqual(recorder.request?.url?.path, "/x/polymer/web-space/seasons_series_list")
    }

    func testWebAndAppQRCodeLoginBuildExpectedRequests() async throws {
        let requestExpectation = expectation(description: "QR login requests captured")
        requestExpectation.expectedFulfillmentCount = 4
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            switch request.url?.path {
            case "/x/passport-login/web/qrcode/generate":
                return Self.response(
                    for: request,
                    body: #"{"code":0,"data":{"url":"https://example.com/web-qr","qrcode_key":"web-key"}}"#
                )
            case "/x/passport-tv-login/qrcode/auth_code":
                return Self.response(
                    for: request,
                    body: #"{"code":0,"data":{"auth_code":"app-key","url":"https://example.com/app-qr"}}"#
                )
            case "/x/passport-tv-login/qrcode/poll":
                return Self.response(for: request, body: #"{"code":86090,"message":"已扫码"}"#)
            case "/x/passport-login/web/qrcode/poll":
                return Self.response(
                    for: request,
                    body: #"{"code":0,"data":{"code":86101,"message":"未扫码"}}"#
                )
            default:
                throw URLError(.badServerResponse)
            }
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "buvid3=test-buvid")
        let webQR = try await api.generateQRCodeLogin()
        let appQR = try await api.generateAppQRCodeLogin()
        let webPoll = try await api.pollQRCodeLogin(qrcodeKey: webQR.qrcodeKey)
        let appPoll = try await api.pollAppQRCodeLogin(authCode: appQR.qrcodeKey)

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(webQR.qrcodeKey, "web-key")
        XCTAssertEqual(appQR.qrcodeKey, "app-key")
        XCTAssertEqual(webPoll.data.status, .waitingForScan)
        XCTAssertEqual(appPoll.status, .waitingForConfirm)

        let webRequest = try XCTUnwrap(
            recorder.requests.first { $0.url?.path == "/x/passport-login/web/qrcode/generate" }
        )
        XCTAssertEqual(webRequest.httpMethod, "GET")
        XCTAssertEqual(webRequest.value(forHTTPHeaderField: "Referer"), "https://passport.bilibili.com/login")

        let webPollRequest = try XCTUnwrap(
            recorder.requests.first { $0.url?.path == "/x/passport-login/web/qrcode/poll" }
        )
        XCTAssertEqual(webPollRequest.httpMethod, "GET")
        XCTAssertEqual(queryValues(for: webPollRequest)["qrcode_key"], "web-key")

        for path in [
            "/x/passport-tv-login/qrcode/auth_code",
            "/x/passport-tv-login/qrcode/poll",
        ] {
            let request = try XCTUnwrap(recorder.requests.first { $0.url?.path == path })
            let values = queryValues(for: request)
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded; charset=utf-8")
            XCTAssertEqual(values["appkey"], "4409e2ce8ffd12b8")
            XCTAssertFalse((values["sign"] ?? "").isEmpty)
            XCTAssertFalse((values["ts"] ?? "").isEmpty)
        }

        let appQRRequest = try XCTUnwrap(
            recorder.requests.first { $0.url?.path == "/x/passport-tv-login/qrcode/auth_code" }
        )
        XCTAssertEqual(queryValues(for: appQRRequest)["local_id"], "0")
        let appPollRequest = try XCTUnwrap(
            recorder.requests.first { $0.url?.path == "/x/passport-tv-login/qrcode/poll" }
        )
        XCTAssertEqual(queryValues(for: appPollRequest)["auth_code"], "app-key")
    }

    func testAppSMSCodeBuildsSignedFormRequest() async throws {
        let requestExpectation = expectation(description: "SMS request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(for: request, body: #"{"code":0,"data":{"captcha_key":"captcha-key"}}"#)
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "buvid3=test-buvid")
        let result = try await api.sendAppSMSCode(phone: "13800138000", countryCode: "852")

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(result.captchaKey, "captcha-key")
        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.url?.path, "/x/passport-login/sms/send")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded; charset=utf-8")
        let requestBuvid = cookieValues(in: request.value(forHTTPHeaderField: "Cookie"))["buvid3"]
        XCTAssertFalse((requestBuvid ?? "").isEmpty)
        let values = formValues(in: request)
        XCTAssertEqual(values["appkey"], "dfca71928277209b")
        XCTAssertEqual(values["buvid"], requestBuvid)
        XCTAssertEqual(values["cid"], "852")
        XCTAssertEqual(values["local_id"], requestBuvid)
        XCTAssertEqual(values["tel"], "13800138000")
        XCTAssertFalse((values["login_session_id"] ?? "").isEmpty)
        XCTAssertFalse((values["sign"] ?? "").isEmpty)
        XCTAssertFalse((values["ts"] ?? "").isEmpty)
    }

    func testFetchNavUserCoalescesConcurrentRequests() async throws {
        let firstRequestExpectation = expectation(description: "first nav request captured")
        let responseRelease = DispatchSemaphore(value: 0)
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            firstRequestExpectation.fulfill()
            _ = responseRelease.wait(timeout: .now() + 2)
            return Self.response(
                for: request,
                body: #"{"code":0,"data":{"isLogin":true,"uname":"测试用户","mid":1001}}"#
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        let firstTask = Task { try await api.fetchNavUser() }
        await fulfillment(of: [firstRequestExpectation], timeout: 2)
        let secondTask = Task { try await api.fetchNavUser() }
        try await Task.sleep(for: .milliseconds(50))
        responseRelease.signal()

        let firstUser = try await firstTask.value
        let secondUser = try await secondTask.value

        XCTAssertEqual(firstUser.mid, 1001)
        XCTAssertEqual(secondUser.mid, 1001)
        XCTAssertEqual(recorder.requests.map(\.url?.path), ["/x/web-interface/nav"])
    }

    func testFetchWBIKeysCoalescesConcurrentRequests() async throws {
        let firstRequestExpectation = expectation(description: "first WBI request captured")
        let responseRelease = DispatchSemaphore(value: 0)
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            firstRequestExpectation.fulfill()
            _ = responseRelease.wait(timeout: .now() + 2)
            return Self.response(
                for: request,
                body:
                    #"{"code":0,"data":{"wbi_img":{"img_url":"https://i.example.com/abc.png","sub_url":"https://i.example.com/def.png"}}}"#
            )
        }
        defer {
            responseRelease.signal()
            RequestContractURLProtocol.reset()
        }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        await api.state.clearWBIKeys()
        let first = Task { try await api.fetchWBIKeys() }
        await fulfillment(of: [firstRequestExpectation], timeout: 2)
        let second = Task { try await api.fetchWBIKeys() }
        try await Task.sleep(for: .milliseconds(20))
        responseRelease.signal()

        let keys = try await [first.value, second.value]

        XCTAssertEqual(keys.map(\.imgKey), ["abc", "abc"])
        XCTAssertEqual(keys.map(\.subKey), ["def", "def"])
        XCTAssertEqual(recorder.requests.map(\.url?.path), ["/x/web-interface/nav"])
    }

    func testFetchPgcSeasonInfoPrefersEpisodeThenFallsBackToSeason() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "PGC season requests captured")
        requestExpectation.expectedFulfillmentCount = 2
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            if Self.queryValue(named: "ep_id", in: request) == "42" {
                return Self.response(
                    for: request,
                    body: #"{"code":-404,"message":"episode not found","result":null}"#
                )
            }
            return Self.response(
                for: request,
                body: #"{"code":0,"result":{"season_id":120,"title":"PGC fallback"}}"#
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        let season = try await api.fetchPgcSeasonInfo(seasonID: 120, epID: 42)

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(season.seasonID, 120)
        let requests = recorder.requests.filter { $0.url?.path == "/pgc/view/web/season" }
        XCTAssertEqual(requests.count, 2)
        let requestsByParameter = Dictionary(
            uniqueKeysWithValues: requests.compactMap { request in
                let query = queryValues(for: request)
                if let epID = query["ep_id"] {
                    return ("ep_id", (epID, request))
                }
                if let seasonID = query["season_id"] {
                    return ("season_id", (seasonID, request))
                }
                return nil
            }
        )
        XCTAssertEqual(requestsByParameter["ep_id"]?.0, "42")
        XCTAssertEqual(requestsByParameter["season_id"]?.0, "120")
        XCTAssertEqual(
            requestsByParameter["ep_id"]?.1.value(forHTTPHeaderField: "Referer"),
            "https://www.bilibili.com/bangumi/play/ep42"
        )
        XCTAssertEqual(
            requestsByParameter["season_id"]?.1.value(forHTTPHeaderField: "Referer"),
            "https://www.bilibili.com/bangumi/play/ss120"
        )
    }

    func testFetchPgcPlayURLBuildsSignedTargetQualityRequestAndDecodesDASH() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()
        let defaults = UserDefaults.standard
        let previousPreference = defaults.object(forKey: VideoCodecPreference.storageKey)
        defaults.set(VideoCodecPreference.forceH264.rawValue, forKey: VideoCodecPreference.storageKey)
        defer {
            if let previousPreference {
                defaults.set(previousPreference, forKey: VideoCodecPreference.storageKey)
            } else {
                defaults.removeObject(forKey: VideoCodecPreference.storageKey)
            }
            RequestContractURLProtocol.reset()
        }

        let requestExpectation = expectation(description: "PGC signed play URL request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            if request.url?.path == "/x/web-interface/nav" {
                return Self.response(
                    for: request,
                    body:
                        #"{"code":0,"data":{"wbi_img":{"img_url":"https://i.example.com/abc.png","sub_url":"https://i.example.com/def.png"}}}"#
                )
            }
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body:
                    #"{"code":0,"result":{"video_info":{"code":0,"quality":80,"accept_quality":[80],"dash":{"video":[{"id":80,"base_url":"https://video.example.com/video.m4s","codecs":"avc1.640028","codecid":7,"mime_type":"video/mp4"}],"audio":[{"id":30280,"base_url":"https://audio.example.com/audio.m4s","codecs":"mp4a.40.2","mime_type":"audio/mp4"}]}}}}"#
            )
        }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        let data = try await api.fetchPgcPlayURL(
            bvid: "BV1PGCtest",
            cid: 24680,
            seasonID: 120,
            epID: 42,
            preferredQuality: 80
        )

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(data.quality, 80)
        XCTAssertEqual(data.dash?.video?.first?.id, 80)
        XCTAssertEqual(data.dash?.bestAudioStream?.id, 30280)
        let request = try XCTUnwrap(
            recorder.requests.first(where: { $0.url?.path == "/pgc/player/web/v2/playurl" })
        )
        let query = queryValues(for: request)
        XCTAssertEqual(query["bvid"], "BV1PGCtest")
        XCTAssertEqual(query["cid"], "24680")
        XCTAssertEqual(query["season_id"], "120")
        XCTAssertEqual(query["ep_id"], "42")
        XCTAssertEqual(query["qn"], "80")
        XCTAssertEqual(query["fnval"], "4048")
        XCTAssertEqual(query["platform"], "iphone")
        XCTAssertEqual(query["video_codecid"], "7")
        XCTAssertNotNil(query["w_rid"])
        XCTAssertNotNil(query["wts"])
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Referer"),
            "https://www.bilibili.com/bangumi/play/ep42"
        )
    }

    func testFetchPgcPlayURLPropagatesMissingPayload() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()
        let defaults = UserDefaults.standard
        let previousPreference = defaults.object(forKey: VideoCodecPreference.storageKey)
        defaults.set(VideoCodecPreference.forceH264.rawValue, forKey: VideoCodecPreference.storageKey)
        defer {
            if let previousPreference {
                defaults.set(previousPreference, forKey: VideoCodecPreference.storageKey)
            } else {
                defaults.removeObject(forKey: VideoCodecPreference.storageKey)
            }
            RequestContractURLProtocol.reset()
        }

        let requestExpectation = expectation(description: "PGC missing payload request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            if request.url?.path == "/x/web-interface/nav" {
                return Self.response(
                    for: request,
                    body:
                        #"{"code":0,"data":{"wbi_img":{"img_url":"https://i.example.com/abc.png","sub_url":"https://i.example.com/def.png"}}}"#
                )
            }
            requestExpectation.fulfill()
            return Self.response(for: request, body: #"{"code":0,"result":{}}"#)
        }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        do {
            _ = try await api.fetchPgcPlayURL(
                bvid: "BV1PGCtest",
                cid: 24680,
                seasonID: 120,
                epID: 42,
                preferredQuality: 80
            )
            XCTFail("Expected missing PGC play URL payload")
        } catch let error as BiliAPIError {
            guard case .missingPayload = error else {
                return XCTFail("Unexpected API error: \(error)")
            }
        }

        await fulfillment(of: [requestExpectation], timeout: 2)
        XCTAssertNotNil(
            recorder.requests.first(where: { $0.url?.path == "/pgc/player/web/v2/playurl" })
        )
    }

    func testFetchPlayURLUsesPreferredQualityBuildsSignedRequestAndDecodesDASH() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()
        let defaults = UserDefaults.standard
        let previousPreference = defaults.object(forKey: VideoCodecPreference.storageKey)
        defaults.set(VideoCodecPreference.forceH264.rawValue, forKey: VideoCodecPreference.storageKey)
        defer {
            if let previousPreference {
                defaults.set(previousPreference, forKey: VideoCodecPreference.storageKey)
            } else {
                defaults.removeObject(forKey: VideoCodecPreference.storageKey)
            }
            RequestContractURLProtocol.reset()
        }

        let requestExpectation = expectation(description: "video play URL request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            if request.url?.path == "/x/web-interface/nav" {
                return Self.response(
                    for: request,
                    body:
                        #"{"code":0,"data":{"wbi_img":{"img_url":"https://i.example.com/abc.png","sub_url":"https://i.example.com/def.png"}}}"#
                )
            }
            requestExpectation.fulfill()
            return Self.response(for: request, body: Self.playableDASHResponse(quality: 80))
        }

        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001",
            playURLCache: PlayURLCache()
        )
        let data = try await api.fetchPlayURL(
            bvid: "BV1videoContract",
            cid: 24_680,
            qn: 112,
            preferredQuality: 80
        )

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(data.quality, 80)
        XCTAssertEqual(data.dash?.video?.first?.id, 80)
        XCTAssertEqual(data.dash?.bestAudioStream?.id, 30_280)
        let request = try XCTUnwrap(
            recorder.requests.first(where: { $0.url?.path == "/x/player/wbi/playurl" })
        )
        let query = queryValues(for: request)
        XCTAssertEqual(query["bvid"], "BV1videoContract")
        XCTAssertEqual(query["cid"], "24680")
        XCTAssertEqual(query["qn"], "80")
        XCTAssertEqual(query["fnval"], "4048")
        XCTAssertEqual(query["video_codecid"], "7")
        XCTAssertNotNil(query["w_rid"])
        XCTAssertNotNil(query["wts"])
    }

    func testFetchPlayURLReusesMemoryCacheForSameKey() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()
        let defaults = UserDefaults.standard
        let previousPreference = defaults.object(forKey: VideoCodecPreference.storageKey)
        defaults.set(VideoCodecPreference.forceH264.rawValue, forKey: VideoCodecPreference.storageKey)
        defer {
            if let previousPreference {
                defaults.set(previousPreference, forKey: VideoCodecPreference.storageKey)
            } else {
                defaults.removeObject(forKey: VideoCodecPreference.storageKey)
            }
            RequestContractURLProtocol.reset()
        }

        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            if request.url?.path == "/x/web-interface/nav" {
                return Self.response(
                    for: request,
                    body:
                        #"{"code":0,"data":{"wbi_img":{"img_url":"https://i.example.com/abc.png","sub_url":"https://i.example.com/def.png"}}}"#
                )
            }
            return Self.response(for: request, body: Self.playableDASHResponse(quality: 80))
        }

        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001",
            playURLCache: PlayURLCache()
        )
        _ = try await api.fetchPlayURL(bvid: "BV1videoCache", cid: 24_681, preferredQuality: 80)
        _ = try await api.fetchPlayURL(bvid: "BV1videoCache", cid: 24_681, preferredQuality: 80)

        XCTAssertEqual(
            recorder.requests.filter { $0.url?.path == "/x/player/wbi/playurl" }.count,
            1
        )
    }

    func testFetchPlayURLMergesConcurrentRequestsForSameKey() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()
        let defaults = UserDefaults.standard
        let previousPreference = defaults.object(forKey: VideoCodecPreference.storageKey)
        defaults.set(VideoCodecPreference.forceH264.rawValue, forKey: VideoCodecPreference.storageKey)
        defer {
            if let previousPreference {
                defaults.set(previousPreference, forKey: VideoCodecPreference.storageKey)
            } else {
                defaults.removeObject(forKey: VideoCodecPreference.storageKey)
            }
            RequestContractURLProtocol.reset()
        }

        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            if request.url?.path == "/x/web-interface/nav" {
                return Self.response(
                    for: request,
                    body:
                        #"{"code":0,"data":{"wbi_img":{"img_url":"https://i.example.com/abc.png","sub_url":"https://i.example.com/def.png"}}}"#
                )
            }
            Thread.sleep(forTimeInterval: 0.15)
            return Self.response(for: request, body: Self.playableDASHResponse(quality: 80))
        }

        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001",
            playURLCache: PlayURLCache()
        )
        async let first = api.fetchPlayURL(bvid: "BV1videoPending", cid: 24_682, preferredQuality: 80)
        async let second = api.fetchPlayURL(bvid: "BV1videoPending", cid: 24_682, preferredQuality: 80)
        let results = try await [first, second]

        XCTAssertEqual(results.map(\.quality), [80, 80])
        XCTAssertEqual(
            recorder.requests.filter { $0.url?.path == "/x/player/wbi/playurl" }.count,
            1
        )
    }

    func testFetchPopularVideosBuildsPagedRequestAndDecodesItems() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()
        let requestExpectation = expectation(description: "popular videos request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body: #"{"code":0,"data":{"list":[{"bvid":"BV1popular","aid":1001,"title":"热门视频"}]}}"#
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        let videos = try await api.fetchPopularVideos(page: 3)

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(videos.map(\.bvid), ["BV1popular"])
        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.url?.path, "/x/web-interface/popular")
        XCTAssertEqual(queryValues(for: request), ["pn": "3", "ps": "20"])
    }

    func testFetchVideoDetailBVIDCoalescesConcurrentRequests() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()
        let recorder = RequestContractRecorder()
        let firstRequestStarted = expectation(description: "first video detail request started")
        let secondCallStarted = expectation(description: "second video detail call started")
        let responseGate = DispatchSemaphore(value: 0)
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            if request.url?.path == "/x/web-interface/view" {
                firstRequestStarted.fulfill()
                _ = responseGate.wait(timeout: .now() + 5)
            }
            return Self.response(
                for: request,
                body: Self.videoItemResponse(bvid: "BV1detail", aid: 1002)
            )
        }
        defer {
            responseGate.signal()
            RequestContractURLProtocol.reset()
        }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        let first = Task { try await api.fetchVideoDetail(bvid: "BV1detail") }
        await fulfillment(of: [firstRequestStarted], timeout: 2)
        let second = Task {
            secondCallStarted.fulfill()
            return try await api.fetchVideoDetail(bvid: "BV1detail")
        }
        await fulfillment(of: [secondCallStarted], timeout: 2)
        try await Task.sleep(for: .milliseconds(20))
        responseGate.signal()
        let details = try await [first.value, second.value]

        XCTAssertEqual(details.map(\.bvid), ["BV1detail", "BV1detail"])
        let requests = recorder.requests.filter { $0.url?.path == "/x/web-interface/view" }
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(queryValues(for: request), ["bvid": "BV1detail"])
        XCTAssertEqual(
            cookieValues(in: request.value(forHTTPHeaderField: "Cookie"))["SESSDATA"],
            "session-value"
        )
    }

    func testFetchVideoDetailAIDBuildsRequestAndDecodes() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()
        let requestExpectation = expectation(description: "AID video detail request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body: Self.videoItemResponse(bvid: "BV1aid", aid: 1003)
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        let detail = try await api.fetchVideoDetail(aid: 1003)

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(detail.bvid, "BV1aid")
        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.url?.path, "/x/web-interface/view")
        XCTAssertEqual(queryValues(for: request), ["aid": "1003"])
    }

    func testFetchVideoRelatedBuildsGuestScopedRequestAndDecodes() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()
        let requestExpectation = expectation(description: "related videos request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body: #"{"code":0,"data":[{"bvid":"BV1related","aid":1004,"title":"相关推荐"}]}"#
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001",
            guestModeEnabled: true
        )
        let videos = try await api.fetchVideoRelated(bvid: "BV1source")

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(videos.map(\.bvid), ["BV1related"])
        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.url?.path, "/x/web-interface/archive/related")
        XCTAssertEqual(
            queryValues(for: request),
            ["bvid": "BV1source", "pn": "1", "ps": "40"]
        )
        let cookies = cookieValues(in: request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNotNil(cookies["buvid3"])
        XCTAssertNil(cookies["SESSDATA"])
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), BiliAPIClient.webUserAgent)
    }

    func testFetchVideoShotNormalizesBVIDAndDecodesMetadata() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()
        let requestExpectation = expectation(description: "video shot request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body:
                    #"{"code":0,"data":{"img_x_len":10,"img_y_len":10,"img_x_size":160,"img_y_size":90,"image":["https://image.example.com/shot.jpg"],"index":[0,10]}}"#
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        let metadata = try await api.fetchVideoShot(bvid: " BV1shot ", cid: 1005)

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertTrue(metadata.isUsable)
        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.url?.path, "/x/player/videoshot")
        XCTAssertEqual(
            queryValues(for: request),
            ["bvid": "BV1shot", "cid": "1005", "index": "1"]
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://www.bilibili.com/video/BV1shot")
        XCTAssertEqual(
            cookieValues(in: request.value(forHTTPHeaderField: "Cookie"))["SESSDATA"],
            "session-value"
        )
    }

    func testFetchDanmakuBuildsXMLRequestParsesAndUsesResourceCache() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()
        await SubtitleDanmakuResourceCache.shared.clear()

        let requestExpectation = expectation(description: "XML danmaku request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body: #"<?xml version="1.0"?><i><d p="1.5,1,25,16777215,0,0,0,42">测试弹幕</d></i>"#
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let cid = 9_100_001
        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001",
            guestModeEnabled: true
        )
        let first = try await api.fetchDanmaku(cid: cid)
        let second = try await api.fetchDanmaku(cid: cid)

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(first.map(\.text), ["测试弹幕"])
        XCTAssertEqual(second, first)
        XCTAssertEqual(recorder.requests.count, 1)
        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.url?.host, "comment.bilibili.com")
        XCTAssertEqual(request.url?.path, "/\(cid).xml")
        XCTAssertNil(request.url?.query)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://www.bilibili.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), BiliAPIClient.webUserAgent)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/xml,text/xml,*/*")
        XCTAssertEqual(request.cachePolicy, .returnCacheDataElseLoad)
        XCTAssertEqual(request.timeoutInterval, 8)
        let cookies = cookieValues(in: request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNotNil(cookies["buvid3"])
        XCTAssertNil(cookies["SESSDATA"])

        await SubtitleDanmakuResourceCache.shared.clear()
    }

    func testFetchDanmakuSegmentNormalizesIndexBuildsProtobufRequestAndParses() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()
        await SubtitleDanmakuResourceCache.shared.clear()

        let requestExpectation = expectation(description: "protobuf danmaku request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(for: request, data: Self.protobufDanmakuSegmentData())
        }
        defer { RequestContractURLProtocol.reset() }

        let cid = 9_100_002
        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001",
            guestModeEnabled: true
        )
        let items = try await api.fetchDanmakuSegment(cid: cid, segmentIndex: 0)

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(items.map(\.id), ["\(cid)-seg1-42"])
        XCTAssertEqual(items.map(\.text), ["分段弹幕"])
        XCTAssertEqual(items.first?.time, 1.5)
        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.url?.host, "api.bilibili.com")
        XCTAssertEqual(request.url?.path, "/x/v2/dm/web/seg.so")
        XCTAssertEqual(
            queryValues(for: request),
            ["type": "1", "oid": "\(cid)", "segment_index": "1"]
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://www.bilibili.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), BiliAPIClient.webUserAgent)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/octet-stream,*/*")
        XCTAssertEqual(request.cachePolicy, .returnCacheDataElseLoad)
        XCTAssertEqual(request.timeoutInterval, 8)
        let cookies = cookieValues(in: request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNotNil(cookies["buvid3"])
        XCTAssertNil(cookies["SESSDATA"])

        await SubtitleDanmakuResourceCache.shared.clear()
    }

    func testFetchLiveRoomsBuildsAnonymousRequestAndDecodesFallbackRoomList() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "live recommendation request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body: """
                    {"code":0,"data":{"list":[{"roomid":31415,"title":"直播测试","uname":"主播","live_status":1}]}}
                    """
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001; buvid3=live-guest-buvid"
        )
        let rooms = try await api.fetchLiveRooms(page: 3, refreshIndex: 7)

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(rooms.map(\.roomID), [31_415])
        let request = try XCTUnwrap(recorder.request)
        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(url.host, "api.live.bilibili.com")
        XCTAssertEqual(url.path, "/xlive/web-interface/v1/webMain/getMoreRecList")
        let query = queryValues(in: components)
        XCTAssertEqual(query["platform"], "web")
        XCTAssertEqual(query["page"], "3")
        XCTAssertEqual(query["page_size"], "20")
        XCTAssertEqual(query["fresh_idx"], "7")
        XCTAssertEqual(query["fresh_type"], "3")
        XCTAssertNotNil(query["_"])
        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://live.bilibili.com")
        XCTAssertEqual(cookieValues(in: request.value(forHTTPHeaderField: "Cookie"))["buvid3"], "live-guest-buvid")
        XCTAssertNil(cookieValues(in: request.value(forHTTPHeaderField: "Cookie"))["SESSDATA"])
    }

    func testFetchLiveRoomInfoBuildsRoomScopedRequestAndDecodes() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "live room info request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body: """
                    {"code":0,"data":{"room_id":24680,"uid":1001,"title":"直播间","live_status":1,"online":12}}
                    """
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        let info = try await api.fetchLiveRoomInfo(roomID: 24_680)

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(info.roomID, 24_680)
        XCTAssertEqual(info.title, "直播间")
        let request = try XCTUnwrap(recorder.request)
        let url = try XCTUnwrap(request.url)
        XCTAssertEqual(url.host, "api.live.bilibili.com")
        XCTAssertEqual(url.path, "/room/v1/Room/get_info")
        XCTAssertEqual(queryValues(for: request), ["room_id": "24680"])
        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://live.bilibili.com/24680")
    }

    func testFetchLiveStreamInfoBuildsWebAndAndroidRequestsAndDecodesCandidate() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "web and android live play requests captured")
        requestExpectation.expectedFulfillmentCount = 2
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            let platform = Self.queryValue(named: "platform", in: request)
            if platform == "web" {
                return Self.response(
                    for: request,
                    body: """
                        {"code":0,"data":{"playurl_info":{"playurl":{"stream":[],"g_qn_desc":[{"qn":10000,"desc":"原画"}]}}}}
                        """
                )
            }
            return Self.response(
                for: request,
                body: """
                    {"code":0,"data":{"playurl_info":{"playurl":{"stream":[{"protocol_name":"http_hls","format":[{"format_name":"fmp4","codec":[{"codec_name":"avc","current_qn":10000,"accept_qn":[10000],"base_url":"/live.m3u8","url_info":[{"host":"https://live.example.com","extra":"?token=android"}]}]}]}],"g_qn_desc":[{"qn":10000,"desc":"原画"}]}}}}
                    """
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        let result = try await api.fetchLiveStreamInfo(roomID: 13_579, quality: 10_000)

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(
            result.candidates.map(\.url.absoluteString), ["https://live.example.com/live.m3u8?token=android"])
        XCTAssertEqual(result.playableQualities.map(\.qn), [10_000])
        let requests = recorder.requests.filter {
            $0.url?.path == "/xlive/web-room/v2/index/getRoomPlayInfo"
        }
        XCTAssertEqual(requests.count, 2)
        let queriesByPlatform = Dictionary(
            uniqueKeysWithValues: requests.compactMap { request in
                Self.queryValue(named: "platform", in: request).map { ($0, queryValues(for: request)) }
            })
        XCTAssertEqual(queriesByPlatform["web"]?["room_id"], "13579")
        XCTAssertEqual(queriesByPlatform["web"]?["protocol"], "0,1")
        XCTAssertEqual(queriesByPlatform["web"]?["format"], "0,1,2")
        XCTAssertEqual(queriesByPlatform["web"]?["codec"], "0,1")
        XCTAssertEqual(queriesByPlatform["web"]?["qn"], "10000")
        XCTAssertEqual(queriesByPlatform["android"]?["room_id"], "13579")
        XCTAssertEqual(queriesByPlatform["android"]?["protocol"], "0,1")
        XCTAssertEqual(queriesByPlatform["android"]?["format"], "0,1,2")
        XCTAssertEqual(queriesByPlatform["android"]?["codec"], "0")
        XCTAssertEqual(queriesByPlatform["android"]?["qn"], "10000")
    }

    func testFetchLiveDanmakuConnectionInfoUsesTransportSessionAndDecodesToken() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "live danmaku request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            guard request.url?.host == "api.live.bilibili.com" else {
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
                    {"code":0,"data":{"token":"live-token","host_list":[{"host":"broadcast.example.com","wss_port":443}]}}
                    """
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RequestContractURLProtocol.self]
        configuration.urlCache = nil
        let transportSession = URLSession(configuration: configuration)
        let info = try await api.fetchLiveDanmakuConnectionInfo(
            roomID: 97531,
            cookieHeader: "SESSDATA=transport-session",
            transportSession: transportSession
        )

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(info.token, "live-token")
        XCTAssertEqual(info.hostList.first?.host, "broadcast.example.com")
        let request = try XCTUnwrap(
            recorder.requests.last(where: { $0.url?.host == "api.live.bilibili.com" })
        )
        let url = try XCTUnwrap(request.url)
        XCTAssertEqual(url.path, "/xlive/web-room/v1/index/getDanmuInfo")
        let query = queryValues(for: request)
        XCTAssertEqual(query["id"], "97531")
        XCTAssertEqual(query["type"], "0")
        XCTAssertEqual(query["web_location"], "444.8")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "SESSDATA=transport-session")
    }

    func testHomeRecommendWebBuildsSignedPaginationAndLimitRequest() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            if request.url?.path == "/x/web-interface/nav" {
                return Self.response(
                    for: request,
                    body:
                        #"{"code":0,"data":{"wbi_img":{"img_url":"https://i.example.com/abc.png","sub_url":"https://i.example.com/def.png"}}}"#
                )
            }
            return Self.response(for: request, body: #"{"code":0,"data":{"item":[]}}"#)
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001",
            recommendSource: .web
        )
        let videos = try await api.fetchRecommendFeed(freshIndex: 9, limit: 99)

        XCTAssertTrue(videos.isEmpty)
        let request = try XCTUnwrap(
            recorder.requests.first(where: { $0.url?.path == "/x/web-interface/wbi/index/top/feed/rcmd" })
        )
        let query = queryValues(for: request)
        XCTAssertEqual(query["fresh_idx"], "9")
        XCTAssertEqual(query["brush"], "9")
        XCTAssertEqual(query["fresh_idx_1h"], "9")
        XCTAssertEqual(query["fresh_type"], "4")
        XCTAssertEqual(query["ps"], "50")
        XCTAssertNotNil(query["w_rid"])
        XCTAssertNotNil(query["wts"])
    }

    func testHomeRecommendAppGuestFallsBackToWebWithoutAccessKey() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            switch request.url?.path {
            case "/x/v2/feed/index":
                return Self.response(for: request, body: #"{"code":0,"data":{"item":[]}}"#)
            case "/x/web-interface/nav":
                return Self.response(
                    for: request,
                    body:
                        #"{"code":0,"data":{"wbi_img":{"img_url":"https://i.example.com/abc.png","sub_url":"https://i.example.com/def.png"}}}"#
                )
            default:
                return Self.response(for: request, body: #"{"code":0,"data":{"item":[]}}"#)
            }
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001",
            accessKey: "app-access-key",
            guestModeEnabled: true,
            recommendSource: .app
        )
        let videos = try await api.fetchRecommendFeed(freshIndex: 4, limit: 3)

        XCTAssertTrue(videos.isEmpty)
        let appRequests = recorder.requests.filter { $0.url?.path == "/x/v2/feed/index" }
        XCTAssertEqual(appRequests.count, 2)
        for request in appRequests {
            let query = queryValues(for: request)
            XCTAssertEqual(query["idx"], "4")
            XCTAssertEqual(query["ps"], "3")
            XCTAssertEqual(query["page_size"], "3")
            XCTAssertEqual(query["login_event"], "0")
            XCTAssertNil(query["access_key"])
        }
        XCTAssertNotNil(
            recorder.requests.first(where: { $0.url?.path == "/x/web-interface/wbi/index/top/feed/rcmd" })
        )
    }

    func testHomeRecommendAppReturnsPrimaryProfileResultWithoutWebFallback() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            return Self.response(
                for: request,
                body:
                    #"{"code":0,"data":{"item":[{"id":123,"bvid":"BV1HomeFeedTest","title":"推荐视频","goto":"av","idx":12}]}}"#
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001",
            accessKey: "app-access-key",
            recommendSource: .app
        )
        let videos = try await api.fetchRecommendFeed(freshIndex: 0, limit: 1)

        XCTAssertEqual(videos.map(\.bvid), ["BV1HomeFeedTest"])
        let appRequests = recorder.requests.filter { $0.url?.path == "/x/v2/feed/index" }
        XCTAssertEqual(appRequests.count, 1)
        XCTAssertEqual(queryValues(for: try XCTUnwrap(appRequests.first))["access_key"], "app-access-key")
        XCTAssertNil(
            recorder.requests.first(where: { $0.url?.path == "/x/web-interface/wbi/index/top/feed/rcmd" })
        )
    }

    func testHomeRecommendAppAPIErrorsFallBackToWeb() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            switch request.url?.path {
            case "/x/v2/feed/index":
                return Self.response(for: request, body: #"{"code":-500,"message":"app failed"}"#)
            case "/x/web-interface/nav":
                return Self.response(
                    for: request,
                    body:
                        #"{"code":0,"data":{"wbi_img":{"img_url":"https://i.example.com/abc.png","sub_url":"https://i.example.com/def.png"}}}"#
                )
            default:
                return Self.response(
                    for: request,
                    body:
                        #"{"code":0,"data":{"item":[{"id":456,"bvid":"BV1HomeFallback","title":"网页兜底视频","goto":"av"}]}}"#
                )
            }
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001",
            accessKey: "app-access-key",
            recommendSource: .app
        )
        let videos = try await api.fetchRecommendFeed(freshIndex: 5, limit: 2)

        XCTAssertEqual(videos.map(\.bvid), ["BV1HomeFallback"])
        XCTAssertEqual(recorder.requests.filter { $0.url?.path == "/x/v2/feed/index" }.count, 2)
        XCTAssertEqual(
            recorder.requests.filter { $0.url?.path == "/x/web-interface/wbi/index/top/feed/rcmd" }.count,
            1
        )
    }

    func testHomeRecommendCoalescesConcurrentIdenticalRequests() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            if request.url?.path == "/x/web-interface/nav" {
                return Self.response(
                    for: request,
                    body:
                        #"{"code":0,"data":{"wbi_img":{"img_url":"https://i.example.com/abc.png","sub_url":"https://i.example.com/def.png"}}}"#
                )
            }
            Thread.sleep(forTimeInterval: 0.15)
            return Self.response(for: request, body: #"{"code":0,"data":{"item":[]}}"#)
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001", recommendSource: .web)
        async let first = api.fetchRecommendFeed(freshIndex: 6, limit: 8)
        async let second = api.fetchRecommendFeed(freshIndex: 6, limit: 8)
        let results = try await [first, second]

        XCTAssertEqual(results.map(\.count), [0, 0])
        XCTAssertEqual(
            recorder.requests.filter { $0.url?.path == "/x/web-interface/wbi/index/top/feed/rcmd" }.count,
            1
        )
    }

    func testVideoHistoryReportsWebHeartbeatBodyAndReferer() async throws {
        let requestExpectation = expectation(description: "history heartbeat request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(for: request, body: #"{"code":0,"data":null}"#)
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001; bili_jct=csrf-value; buvid3=buvid-value"
        )
        try await api.reportVideoHistory(
            aid: 123,
            cid: 456,
            progress: 12.9,
            duration: 300.8,
            bvid: "  BV1TEST  "
        )

        await fulfillment(of: [requestExpectation], timeout: 2)

        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.url?.path, "/x/click-interface/web/heartbeat")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://www.bilibili.com/video/BV1TEST")
        XCTAssertEqual(
            formValues(in: request),
            [
                "bvid": "BV1TEST",
                "cid": "456",
                "csrf": "csrf-value",
                "played_time": "12",
                "type": "3",
            ]
        )
        XCTAssertEqual(cookieValues(in: request.value(forHTTPHeaderField: "Cookie"))["SESSDATA"], "session-value")
    }

    func testRequireCSRFReturnsMainAccountToken() async throws {
        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001; bili_jct=csrf-value"
        )

        let csrf = try await api.requireCSRF()
        XCTAssertEqual(csrf, "csrf-value")
    }

    func testRequireCSRFRejectsLoggedOutSession() async throws {
        let api = try makeAPI(cookieHeader: "")

        do {
            _ = try await api.requireCSRF()
            XCTFail("Expected missing login credential")
        } catch let error as BiliAPIError {
            guard case .missingSESSDATA = error else {
                return XCTFail("Unexpected API error: \(error)")
            }
        }
    }

    func testRequireCSRFRejectsAuthenticatedSessionWithoutToken() async throws {
        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")

        do {
            _ = try await api.requireCSRF()
            XCTFail("Expected missing CSRF token")
        } catch let error as BiliAPIError {
            guard case .missingCSRF = error else {
                return XCTFail("Unexpected API error: \(error)")
            }
        }
    }

    func testVideoHistoryFallsBackFromHeartbeatToWebHistory() async throws {
        let requestExpectation = expectation(description: "history fallback requests captured")
        requestExpectation.expectedFulfillmentCount = 2
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            if request.url?.path == "/x/click-interface/web/heartbeat" {
                return Self.response(for: request, body: #"{"code":-1,"message":"heartbeat failed","data":null}"#)
            }
            return Self.response(for: request, body: #"{"code":0,"data":null}"#)
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001; bili_jct=csrf-value")
        try await api.reportVideoHistory(aid: 123, cid: 456, progress: 42, duration: 120)

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(
            recorder.requests.map { $0.url?.path },
            [
                "/x/click-interface/web/heartbeat",
                "/x/v2/history/report",
            ])
        let request = try XCTUnwrap(recorder.requests.last)
        XCTAssertEqual(
            formValues(in: request),
            [
                "aid": "123",
                "cid": "456",
                "csrf": "csrf-value",
                "duration": "120",
                "ga": "1",
                "gaia_source": "web_normal",
                "progress": "42",
                "type": "3",
            ]
        )
    }

    func testVideoHistoryUsesSignedAppAccessKeyRouteWhenWebCredentialIsUnavailable() async throws {
        let requestExpectation = expectation(description: "app history request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(for: request, body: #"{"code":0,"data":null}"#)
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001; buvid3=buvid-value",
            accessKey: "app-access-key"
        )
        try await api.reportVideoHistory(aid: 123, cid: 456, progress: 7, duration: 80)

        await fulfillment(of: [requestExpectation], timeout: 2)

        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.url?.path, "/x/v2/history/report")
        XCTAssertEqual(request.value(forHTTPHeaderField: "app-key"), "android")
        let fields = formValues(in: request)
        XCTAssertEqual(fields["access_key"], "app-access-key")
        XCTAssertEqual(fields["aid"], "123")
        XCTAssertEqual(fields["cid"], "456")
        XCTAssertEqual(fields["duration"], "80")
        XCTAssertEqual(fields["gaia_source"], "app_normal")
        XCTAssertEqual(fields["progress"], "7")
        XCTAssertEqual(fields["type"], "3")
        XCTAssertNotNil(fields["sign"])
        XCTAssertNotNil(fields["ts"])
    }

    func testOfficialVideoListenPlaylistBuildsCursorQualityAndSortRequest() async throws {
        let requestExpectation = expectation(description: "official listen playlist request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            let responseMessage = Data([0x10, 0x01, 0x18, 0x01])
            return Self.response(for: request, data: BiliListenerPlaylistCodec.frame(responseMessage))
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001; buvid3=buvid-value",
            accessKey: "app-access-key"
        )
        let page = try await api.fetchOfficialVideoListenPlaylist(
            aid: 123,
            cid: 456,
            cursor: "  cursor-token  ",
            sortOrder: .reverse
        )

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertTrue(page.reachedStart)
        XCTAssertTrue(page.reachedEnd)
        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.url?.host, "app.bilibili.com")
        XCTAssertEqual(request.url?.path, BiliListenerPlaylistCodec.endpointPath)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "identify_v1 app-access-key")
        let expectedBody = try BiliListenerPlaylistCodec.encodeRequest(
            aid: 123,
            cid: 456,
            cursor: "cursor-token",
            sortOrder: .reverse
        )
        XCTAssertEqual(requestBodyData(from: request), BiliListenerPlaylistCodec.frame(expectedBody))
    }

    func testOfficialVideoListenPlaylistRejectsInvalidAnchorBeforeRequest() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            return Self.response(for: request, data: Data())
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001", accessKey: "app-access-key")
        do {
            _ = try await api.fetchOfficialVideoListenPlaylist(aid: 123, cid: nil)
            XCTFail("Expected invalid anchor")
        } catch let error as BiliListenerPlaylistError {
            XCTAssertEqual(error, .invalidAnchor)
        }
        XCTAssertTrue(recorder.requests.isEmpty)
    }

    func testOfficialVideoListenPlaylistRejectsMissingAccessKeyBeforeRequest() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            return Self.response(for: request, data: Data())
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        do {
            _ = try await api.fetchOfficialVideoListenPlaylist(aid: 123, cid: 456)
            XCTFail("Expected missing access key")
        } catch let error as BiliListenerPlaylistError {
            XCTAssertEqual(error, .missingAccessKey)
        }
        XCTAssertTrue(recorder.requests.isEmpty)
    }

    func testOfficialVideoListenPlaylistRejectsHTTPFailureAfterBuvidFallback() async throws {
        let requestExpectation = expectation(description: "official listen playlist HTTP failure captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(for: request, statusCode: 503, data: Data())
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001; buvid4=buvid4-value",
            accessKey: "app-access-key"
        )
        do {
            _ = try await api.fetchOfficialVideoListenPlaylist(aid: 123, cid: 456)
            XCTFail("Expected HTTP failure")
        } catch let error as BiliListenerPlaylistError {
            XCTAssertEqual(error, .invalidHTTPStatus(503))
        }

        await fulfillment(of: [requestExpectation], timeout: 2)
        XCTAssertFalse(recorder.request?.value(forHTTPHeaderField: "buvid")?.isEmpty ?? true)
    }

    func testOfficialVideoListenPlaylistRejectsBiliStatus() async throws {
        RequestContractURLProtocol.install { request in
            Self.response(
                for: request,
                headerFields: [
                    "Content-Type": "application/grpc",
                    "bili-status-code": "7",
                    "bili-status-message": "permission%20denied",
                ],
                data: Data([0])
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001",
            accessKey: "app-access-key"
        )
        do {
            _ = try await api.fetchOfficialVideoListenPlaylist(aid: 123, cid: 456)
            XCTFail("Expected Bili status failure")
        } catch let error as BiliListenerPlaylistError {
            XCTAssertEqual(error, .grpcStatus(7, "permission denied"))
        }
    }

    func testOfficialVideoListenPlaylistRejectsEmptyResponse() async throws {
        RequestContractURLProtocol.install { request in
            Self.response(for: request, data: Data())
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001",
            accessKey: "app-access-key"
        )
        do {
            _ = try await api.fetchOfficialVideoListenPlaylist(aid: 123, cid: 456)
            XCTFail("Expected invalid response")
        } catch let error as BiliListenerPlaylistError {
            XCTAssertEqual(error, .invalidResponse)
        }
    }

    private func makeAPI(
        cookieHeader: String,
        accessKey: String? = nil,
        playURLCache: PlayURLCache = .shared,
        guestModeEnabled: Bool = false,
        recommendSource: HomeRecommendFeedSourcePreference = .web
    ) throws -> BiliAPIClient {
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
        if let accessKey {
            try keychain.save(accessKey, for: "ACCESS_KEY")
        }
        try keychain.save(LoginCredentialKind.web.rawValue, for: "LOGIN_CREDENTIAL_KIND")

        let sessionStore = SessionStore(keychain: keychain)
        if cookieValues["DedeUserID"] != nil {
            try sessionStore.saveLoginCookies(cookieValues, credentialKind: .web)
        }
        let libraryStore = LibraryStore(userDefaults: UserDefaults(suiteName: keychainService)!)
        libraryStore.setGuestModeEnabled(guestModeEnabled)
        libraryStore.setHomeRecommendFeedSourcePreference(recommendSource)
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
            homeRecommendDiagnosticsStore: .shared,
            playURLCache: playURLCache
        )
    }

    private static func response(for request: URLRequest, body: String) -> (HTTPURLResponse, Data) {
        response(for: request, data: Data(body.utf8))
    }

    private static func response(
        for request: URLRequest,
        statusCode: Int = 200,
        headerFields: [String: String] = ["Content-Type": "application/json"],
        data: Data
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headerFields
        )!
        return (response, data)
    }

    private static func protobufDanmakuSegmentData() -> Data {
        let element =
            protobufVarintField(1, value: 42)
            + protobufVarintField(2, value: 1_500)
            + protobufVarintField(3, value: 1)
            + protobufVarintField(4, value: 25)
            + protobufVarintField(5, value: 16_777_215)
            + protobufLengthDelimitedField(7, payload: Array("分段弹幕".utf8))
        return Data(protobufLengthDelimitedField(1, payload: element))
    }

    private static func protobufVarintField(_ fieldNumber: Int, value: UInt64) -> [UInt8] {
        protobufVarint(UInt64(fieldNumber << 3)) + protobufVarint(value)
    }

    private static func protobufLengthDelimitedField(_ fieldNumber: Int, payload: [UInt8]) -> [UInt8] {
        protobufVarint(UInt64((fieldNumber << 3) | 2))
            + protobufVarint(UInt64(payload.count))
            + payload
    }

    private static func protobufVarint(_ value: UInt64) -> [UInt8] {
        var remaining = value
        var bytes = [UInt8]()
        repeat {
            var byte = UInt8(remaining & 0x7F)
            remaining >>= 7
            if remaining != 0 {
                byte |= 0x80
            }
            bytes.append(byte)
        } while remaining != 0
        return bytes
    }

    private static func playableDASHResponse(quality: Int) -> String {
        #"{"code":0,"data":{"quality":\#(quality),"accept_quality":[\#(quality)],"dash":{"video":[{"id":\#(quality),"base_url":"https://video.example.com/video.m4s","codecs":"avc1.640028","codecid":7,"mime_type":"video/mp4"}],"audio":[{"id":30280,"base_url":"https://audio.example.com/audio.m4s","codecs":"mp4a.40.2","mime_type":"audio/mp4"}]}}}"#
    }

    private static func videoItemResponse(bvid: String, aid: Int) -> String {
        #"{"code":0,"data":{"bvid":"\#(bvid)","aid":\#(aid),"title":"视频详情"}}"#
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

    private func queryValues(for request: URLRequest) -> [String: String] {
        guard let url = request.url,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return [:] }
        return queryValues(in: components)
    }

    private static func queryValue(named name: String, in request: URLRequest) -> String? {
        guard let url = request.url,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        return components.queryItems?.first(where: { $0.name == name })?.value
    }

    private func formValues(in request: URLRequest) -> [String: String] {
        guard let body = requestBodyData(from: request),
            let bodyString = String(data: body, encoding: .utf8),
            let components = URLComponents(string: "?\(bodyString)")
        else { return [:] }
        return queryValues(in: components)
    }

    private func requestBodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
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
        [
            "api.bilibili.com", "api.live.bilibili.com", "app.bilibili.com", "comment.bilibili.com",
            "passport.bilibili.com", "space.bilibili.com",
        ].contains(
            request.url?.host)
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
