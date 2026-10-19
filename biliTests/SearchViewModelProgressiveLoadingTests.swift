import Foundation
import XCTest
@testable import bili

@MainActor
final class SearchViewModelProgressiveLoadingTests: XCTestCase {
    func testComprehensiveSearchPublishesVideosBeforeSupplementalResults() async throws {
        let gate = SearchTestGate()
        let user = try JSONDecoder.bili.decode(
            SearchUserItem.self,
            from: Data(#"{"mid":100,"uname":"稍后到达的用户"}"#.utf8)
        )
        let api = SearchAPIStub(user: user, userGate: gate)
        let model = SearchViewModel(api: api)

        let search = Task { await model.search("渐进加载") }
        let didPublishVideo = await eventually {
            model.results.contains { result in
                if case .video(let video) = result {
                    return video.bvid == "BV-progressive"
                }
                return false
            }
        }
        XCTAssertTrue(didPublishVideo)
        XCTAssertTrue(model.state.isLoading)
        XCTAssertFalse(
            model.results.contains { result in
                if case .user = result { return true }
                return false
            }
        )

        await gate.open()
        await search.value

        XCTAssertEqual(model.results.map(\.sectionTitle), ["视频", "UP主"])
        XCTAssertFalse(model.state.isLoading)
    }

    func testComprehensivePaginationKeepsAllVideosBeforeSupplementalResults() async throws {
        let user = try JSONDecoder.bili.decode(
            SearchUserItem.self,
            from: Data(#"{"mid":100,"uname":"搜索用户"}"#.utf8)
        )
        let model = SearchViewModel(api: SearchAPIStub(user: user))
        await model.search("视频优先")
        XCTAssertEqual(model.results.map(\.sectionTitle), ["视频", "UP主"])

        await model.loadMoreIfNeeded(current: model.results.last)

        XCTAssertEqual(model.results.map(\.sectionTitle), ["视频", "视频", "UP主"])
        XCTAssertEqual(model.results.map(\.id), ["video-BV-progressive", "video-BV-page-2", "user-100"])
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

private actor SearchTestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }
}

private actor SearchAPIStub: SearchAPIProviding {
    private let user: SearchUserItem?
    private let userGate: SearchTestGate?
    private(set) var oldSearchStarted = false
    private(set) var oldSearchCancelled = false

    init(user: SearchUserItem? = nil, userGate: SearchTestGate? = nil) {
        self.user = user
        self.userGate = userGate
    }

    func fetchHotSearch() async throws -> [HotSearchItem] { [] }

    func fetchSearchSuggest(term: String) async throws -> [SearchSuggestItem] { [] }

    func searchVideos(keyword: String, page: Int, order: String?) async throws -> [VideoItem] {
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
        if let userGate {
            await userGate.wait()
        }
        return user.map { [$0] } ?? []
    }

    func searchBangumi(keyword: String, page: Int) async throws -> [SearchMediaItem] { [] }

    func searchMovies(keyword: String, page: Int) async throws -> [SearchMediaItem] { [] }

    func searchArticles(keyword: String, page: Int) async throws -> [SearchArticleItem] { [] }
}
