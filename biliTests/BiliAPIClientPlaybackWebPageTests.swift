import XCTest

@testable import bili

final class BiliAPIClientPlaybackWebPageTests: XCTestCase {
    func testExtractBalancedJSONObjectIgnoresBracesAndEscapedQuotesInsideStrings() throws {
        let source = #"""
            prefix {"message":"literal { brace } and escaped quote \\\" stay in string","nested":{"value":true}} suffix
            """#

        let json = try XCTUnwrap(BiliAPIClient.extractBalancedJSONObject(from: source[...]))

        XCTAssertEqual(
            json,
            #"{"message":"literal { brace } and escaped quote \\\" stay in string","nested":{"value":true}}"#
        )
    }
}
