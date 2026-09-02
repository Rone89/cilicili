import XCTest

@testable import bili

@MainActor
final class SearchFeatureTests: XCTestCase {
    func testArticleSearchScopeMetadata() {
        XCTAssertEqual(SearchScope.comprehensive.title, "综合内容")
        XCTAssertEqual(SearchScope.article.title, "专栏")
        XCTAssertEqual(SearchScope.article.systemImage, "doc.text")
        XCTAssertFalse(SearchScope.article.supportsOrder)
        XCTAssertTrue(SearchScope.comprehensive.supportsOrder)
        XCTAssertEqual(SearchSortOrder.comprehensive.title, "综合排序")
    }

    func testRecentPlaybackPreloadGateSuppressesImmediateDuplicates() {
        let gate = RecentPlaybackPreloadGate()
        let start = Date(timeIntervalSince1970: 1_000)

        XCTAssertTrue(gate.shouldBeginPreload(for: "BV1", now: start))
        XCTAssertFalse(gate.shouldBeginPreload(for: "BV1", now: start.addingTimeInterval(1)))
        XCTAssertTrue(gate.shouldBeginPreload(for: "BV1", now: start.addingTimeInterval(1.3)))
    }

    func testSearchControlsOnlyMoveToKeyboardWhenKeyboardIsVisible() {
        let store = SearchBottomAccessoryStore()

        store.isSearchFocused = true
        XCTAssertFalse(store.usesKeyboardControls)

        store.isKeyboardVisible = true
        XCTAssertTrue(store.usesKeyboardControls)

        store.isKeyboardVisible = false
        XCTAssertFalse(store.usesKeyboardControls)
    }
}
