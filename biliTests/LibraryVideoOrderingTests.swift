import XCTest
@testable import bili

final class LibraryVideoOrderingTests: XCTestCase {
    func testDefaultOrderAndSearchKeepServerOrder() throws {
        let entries = try fixture()
        XCTAssertEqual(LibraryVideoOrder.original.arrange(entries).map(\.bvid), entries.map(\.bvid))
        XCTAssertEqual(
            LibraryVideoOrder.original.arrange(entries, query: "  测试UP \n").map(\.bvid),
            ["BVorder2", "BVorder3"]
        )
        XCTAssertEqual(LibraryVideoOrder.original.arrange(entries, query: "BVORDER1").map(\.bvid), ["BVorder1"])
    }

    func testDurationOrderKeepsUnknownLastInBothDirectionsAndTiesStable() throws {
        let entries = try fixture()
        XCTAssertEqual(
            LibraryVideoOrder.shortestFirst.arrange(entries).map(\.bvid),
            ["BVorder2", "BVorder3", "BVorder1", "BVorder4", "BVorder5"]
        )
        XCTAssertEqual(
            LibraryVideoOrder.longestFirst.arrange(entries).map(\.bvid),
            ["BVorder1", "BVorder2", "BVorder3", "BVorder4", "BVorder5"]
        )
    }

    func testTitleOrderAndSearchCanBeCombinedWithoutMutatingSource() throws {
        let entries = try fixture()
        XCTAssertEqual(
            LibraryVideoOrder.titleAscending.arrange(entries, query: "Episode").map(\.bvid),
            ["BVorder2", "BVorder3", "BVorder1"]
        )
        XCTAssertEqual(entries.map(\.bvid), ["BVorder1", "BVorder2", "BVorder3", "BVorder4", "BVorder5"])
    }

    private func fixture() throws -> [AccountVideoEntry] {
        let data = Data("""
        {"list":[
          {"bvid":"BVorder1","aid":1,"title":"Episode 10","duration":600},
          {"bvid":"BVorder2","aid":2,"title":"Episode 2","duration":60,"owner":{"name":"测试UP","mid":9}},
          {"bvid":"BVorder3","aid":3,"title":"Episode 2","duration":60,"owner":{"name":"测试UP","mid":9}},
          {"bvid":"BVorder4","aid":4,"title":"Unknown"},
          {"bvid":"BVorder5","aid":5,"title":"Zero","duration":0}
        ]}
        """.utf8)
        return try JSONDecoder().decode(DynamicJSONValue.self, from: data).accountVideoEntries
    }
}
