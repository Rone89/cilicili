import XCTest
@testable import bili

final class MineSearchCatalogTests: XCTestCase {
    func testSearchMatchesTitlesAndAliases() {
        XCTAssertEqual(
            MineSearchCatalog.search("画质").map(\.id),
            ["playback-settings"]
        )
        XCTAssertEqual(
            MineSearchCatalog.search("图片质量").map(\.id),
            ["interface-settings"]
        )
        XCTAssertEqual(
            MineSearchCatalog.search("多账号").map(\.id),
            ["account-management"]
        )
        XCTAssertEqual(
            MineSearchCatalog.search("应用图标").map(\.id),
            ["interface-settings"]
        )
        XCTAssertEqual(
            MineSearchCatalog.search("热门 搜索").map(\.id),
            ["home-search-settings"]
        )
        XCTAssertEqual(
            MineSearchCatalog.search("强制-120hz").map(\.id),
            ["interface-settings"]
        )
    }

    func testSearchReturnsNoResultsForEmptyOrUnknownQuery() {
        XCTAssertTrue(MineSearchCatalog.search("   ").isEmpty)
        XCTAssertTrue(MineSearchCatalog.search("不存在的设置").isEmpty)
    }
}
