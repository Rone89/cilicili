import Foundation
import XCTest
@testable import bili

@MainActor
final class SearchViewModelProgressiveLoadingTests: XCTestCase {
    func testDefaultSearchRequestsOnlyVideoAndPaginates() async {
        let api = SearchAPIStub()
        let model = SearchViewModel(api: api)
        XCTAssertEqual(model.selectedScope, .video)
        await model.search("默认视频")
        XCTAssertEqual(model.results.map(\.id), ["video-BV-progressive"])
        await model.loadMoreIfNeeded(current: model.results.last)
        XCTAssertEqual(model.results.map(\.id), ["video-BV-progressive", "video-BV-page-2"])
        let calls = await api.requestedScopes
        XCTAssertEqual(calls, [.video, .video])
    }

    func testHotSearchReturnsFromUserScopeToVideoOnly() async {
        let api = SearchAPIStub()
        let model = SearchViewModel(api: api)
        await model.selectScope(.user)
        await model.searchHotSearch(HotSearchItem(keyword: "热搜视频", showName: nil, icon: nil))
        XCTAssertEqual(model.selectedScope, .video)
        XCTAssertEqual(model.query, "热搜视频")
        let calls = await api.requestedScopes
        XCTAssertEqual(calls, [.video])
        XCTAssertEqual(model.results.map(\.sectionTitle), ["视频"])
    }

    func testStartingNewSearchCancelsOldNetworkWorkAndRejectsOldResults() async {
        let api = SearchAPIStub()
        let model = SearchViewModel(api: api)

        let oldSearch = Task { await model.search("旧关键词") }
        let didStartOldSearch = await eventually { await api.oldSearchStarted }
        XCTAssertTrue(didStartOldSearch)

        await model.search("新关键词")
        await oldSearch.value

        let didCancelOldSearch = await eventually { await api.oldSearchCancelled }
        XCTAssertTrue(didCancelOldSearch)
        XCTAssertEqual(
            model.results.compactMap { result -> String? in
                if case .video(let video) = result { return video.bvid }
                return nil
            },
            ["BV-new"]
        )
    }

    func testSwitchingScopeCancelsPendingVideoSearchAndShowsOnlyUsers() async throws {
        let user = try JSONDecoder.bili.decode(
            SearchUserItem.self,
            from: Data(#"{"mid":100,"uname":"目标用户"}"#.utf8)
        )
        let api = SearchAPIStub(user: user)
        let model = SearchViewModel(api: api)
        let oldSearch = Task { await model.search("旧关键词") }
        let started = await eventually { await api.oldSearchStarted }
        XCTAssertTrue(started)

        await model.selectScope(.user)
        await oldSearch.value
        XCTAssertEqual(model.selectedScope, .user)
        XCTAssertEqual(model.query, "旧关键词")
        XCTAssertEqual(model.results.map(\.id), ["user-100"])
        let cancelled = await eventually { await api.oldSearchCancelled }
        XCTAssertTrue(cancelled)

        await model.search("新关键词")
        await model.selectScope(.video)
        XCTAssertEqual(model.results.map(\.id), ["video-BV-new"])
    }

    private func eventually(
        timeout: Duration = .seconds(2),
        condition: @escaping @MainActor () async -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await condition()
    }
}

private actor SearchAPIStub: SearchAPIProviding {
    private let user: SearchUserItem?
    private(set) var oldSearchStarted = false
    private(set) var oldSearchCancelled = false

    private(set) var requestedScopes: [SearchScope] = []

    init(user: SearchUserItem? = nil) {
        self.user = user
    }

    func fetchHotSearch() async throws -> [HotSearchItem] { [] }

    func fetchSearchSuggest(term: String) async throws -> [SearchSuggestItem] { [] }

    func searchVideos(keyword: String, page: Int, order: String?) async throws -> [VideoItem] {
        requestedScopes.append(.video)
        if keyword == "旧关键词" {
            oldSearchStarted = true
            do {
                try await Task.sleep(for: .seconds(30))
            } catch is CancellationError {
                oldSearchCancelled = true
                throw CancellationError()
            }
        }
        let bvid = page > 1 ? "BV-page-\(page)" : (keyword == "新关键词" ? "BV-new" : "BV-progressive")
        return [
            VideoItem(
                bvid: bvid,
                aid: 1,
                title: keyword,
                pic: nil,
                desc: nil,
                duration: 60,
                pubdate: nil,
                owner: nil,
                stat: nil,
                cid: 1,
                pages: nil,
                dimension: nil
            )
        ]
    }

    func searchUsers(keyword: String, page: Int) async throws -> [SearchUserItem] {
        requestedScopes.append(.user)
        return user.map { [$0] } ?? []
    }

    func searchBangumi(keyword: String, page: Int) async throws -> [SearchMediaItem] {
        requestedScopes.append(.bangumi)
        return []
    }

    func searchMovies(keyword: String, page: Int) async throws -> [SearchMediaItem] {
        requestedScopes.append(.movie)
        return []
    }

    func searchArticles(keyword: String, page: Int) async throws -> [SearchArticleItem] {
        requestedScopes.append(.article)
        return []
    }
}
