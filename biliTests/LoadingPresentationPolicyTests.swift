import XCTest
@testable import bili

final class LoadingPresentationPolicyTests: XCTestCase {
    func testIndicatorAppearsOnlyAfterMinimumDelay() {
        XCTAssertFalse(
            LoadingPresentationPolicy.shouldPresentIndicator(after: .milliseconds(299))
        )
        XCTAssertTrue(
            LoadingPresentationPolicy.shouldPresentIndicator(
                after: LoadingPresentationPolicy.minimumIndicatorDelay
            )
        )
    }
}
