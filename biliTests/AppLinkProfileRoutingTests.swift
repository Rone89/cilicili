import XCTest
@testable import bili

final class AppLinkProfileRoutingTests: XCTestCase {
    func testMentionURLPreservesUserIdentity() throws {
        let url = try XCTUnwrap(URL(string: "https://space.bilibili.com/1002?name=%E6%8F%90%E5%8F%8A%E7%94%A8%E6%88%B7"))
        let owner = try XCTUnwrap(AppLinkRouter.userOwner(from: url))
        XCTAssertEqual(owner.mid, 1002)
        XCTAssertEqual(owner.name, "提及用户")
    }

    func testProfileRoutingRejectsOtherLinksAndInvalidUsers() throws {
        for address in [
            "https://www.bilibili.com/video/BV1xx411c7mD",
            "https://example.com/1002",
            "https://space.bilibili.com.evil.example/1002",
            "https://space.bilibili.com/0",
            "https://space.bilibili.com/",
        ] {
            XCTAssertNil(AppLinkRouter.userOwner(from: try XCTUnwrap(URL(string: address))))
        }
    }
}
