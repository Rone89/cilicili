import XCTest

@testable import bili

final class BiliAPIClientAppHeadersTests: XCTestCase {
    func testStableHexTokenRepeatsUTF8ScalarHexUntilRequestedLength() {
        XCTAssertEqual(
            BiliAPIClient.stableHexToken(seed: "ab", length: 10),
            "6162616261"
        )
    }

    func testStableHexTokenUsesFallbackForEmptySeed() {
        XCTAssertEqual(
            BiliAPIClient.stableHexToken(seed: "", length: 8),
            "01234567"
        )
    }
}
