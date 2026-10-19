import XCTest

@testable import bili

@MainActor
final class SearchFeatureTests: XCTestCase {
    func testArticleSearchScopeMetadata() {
        XCTAssertEqual(SearchScope.allCases, [.video, .bangumi, .movie, .article, .user])
        XCTAssertEqual(SearchScope.article.title, "专栏")
        XCTAssertEqual(SearchScope.article.systemImage, "doc.text")
        XCTAssertFalse(SearchScope.article.supportsOrder)
        XCTAssertTrue(SearchScope.video.supportsOrder)
        XCTAssertEqual(SearchSortOrder.comprehensive.title, "综合排序")
    }

    func testRecentPlaybackPreloadGateSuppressesImmediateDuplicates() {
        let gate = RecentPlaybackPreloadGate()
        let start = Date(timeIntervalSince1970: 1_000)

        XCTAssertTrue(gate.shouldBeginPreload(for: "BV1", now: start))
        XCTAssertFalse(gate.shouldBeginPreload(for: "BV1", now: start.addingTimeInterval(1)))
        XCTAssertTrue(gate.shouldBeginPreload(for: "BV1", now: start.addingTimeInterval(1.3)))
    }

    func testSearchControlsFollowNativeSearchFieldFocus() {
        let store = SearchBottomAccessoryStore()
        XCTAssertFalse(store.usesKeyboardControls)
        store.isSearchFocused = true
        XCTAssertTrue(store.usesKeyboardControls)
        store.isSearchFocused = false
        XCTAssertFalse(store.usesKeyboardControls)
    }
}
