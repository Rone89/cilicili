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

    func testExternalSchemesAreAcceptedAndUnwrapped() throws {
        let wrapped = try XCTUnwrap(URL(string: "cilicili://open?url=https%3A%2F%2Fwww.bilibili.com%2Fvideo%2FBV1xx411c7mD"))
        XCTAssertTrue(AppLinkRouter.canHandle(wrapped))
        XCTAssertEqual(
            AppLinkRouter.unwrappedExternalURL(wrapped).absoluteString,
            "https://www.bilibili.com/video/BV1xx411c7mD"
        )

        let videoScheme = try XCTUnwrap(URL(string: "bilibili://video/BV1xx411c7mD?p=2"))
        XCTAssertTrue(AppLinkRouter.canHandle(videoScheme))
        XCTAssertEqual(
            AppLinkRouter.unwrappedExternalURL(videoScheme).absoluteString,
            "https://www.bilibili.com/video/BV1xx411c7mD?p=2"
        )

        let aidScheme = try XCTUnwrap(URL(string: "bilibili://video/170001"))
        XCTAssertEqual(
            AppLinkRouter.unwrappedExternalURL(aidScheme).absoluteString,
            "https://www.bilibili.com/video/av170001"
        )

        let spaceScheme = try XCTUnwrap(URL(string: "bilibili://space/123456"))
        XCTAssertEqual(
            AppLinkRouter.unwrappedExternalURL(spaceScheme).absoluteString,
            "https://space.bilibili.com/123456"
        )

        let articleScheme = try XCTUnwrap(URL(string: "bilibili://article/24680135"))
        XCTAssertEqual(
            AppLinkRouter.unwrappedExternalURL(articleScheme).absoluteString,
            "https://www.bilibili.com/read/cv24680135"
        )

        let liveScheme = try XCTUnwrap(URL(string: "bilibili://live/22637261"))
        XCTAssertEqual(
            AppLinkRouter.unwrappedExternalURL(liveScheme).absoluteString,
            "https://live.bilibili.com/22637261"
        )
    }
}
