import XCTest
@testable import bili

final class WatchLaterViewingFilterTests: XCTestCase {
    func testOnlyConfirmedProgressEntersSpecificFilters() throws {
        let entries = try fixture()
        XCTAssertEqual(entries.filter { WatchLaterViewingFilter.all.includes($0) }.count, 6)
        XCTAssertEqual(entries.filter { WatchLaterViewingFilter.resumable.includes($0) }.map(\.bvid), ["BVstatus1"])
        XCTAssertEqual(entries.filter { WatchLaterViewingFilter.completed.includes($0) }.map(\.bvid), ["BVstatus2"])
    }

    func testSearchAndOrderingCannotBringExcludedItemsBack() throws {
        let entries = try fixture().filter { WatchLaterViewingFilter.completed.includes($0) }
        XCTAssertTrue(LibraryVideoOrder.longestFirst.arrange(entries, query: "BVstatus1").isEmpty)
        XCTAssertEqual(
            LibraryVideoOrder.titleAscending.arrange(entries, query: "Finished").map(\.bvid),
            ["BVstatus2"]
        )
    }

    private func fixture() throws -> [AccountVideoEntry] {
        let data = Data("""
        {"list":[
          {"bvid":"BVstatus1","aid":1,"title":"Resume","duration":120,"progress":30},
          {"bvid":"BVstatus2","aid":2,"title":"Finished","duration":120,"progress":-1},
          {"bvid":"BVstatus3","aid":3,"title":"Not started","duration":120,"progress":0},
          {"bvid":"BVstatus4","aid":4,"title":"Unknown","duration":120},
          {"bvid":"BVstatus5","aid":5,"title":"Near end","duration":120,"progress":110},
          {"bvid":"BVstatus6","aid":6,"title":"Unknown duration","progress":-1}
        ]}
        """.utf8)
        return try JSONDecoder().decode(DynamicJSONValue.self, from: data).accountVideoEntries
    }
}
