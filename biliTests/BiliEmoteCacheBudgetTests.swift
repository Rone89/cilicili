import XCTest
@testable import bili

final class BiliEmoteCacheBudgetTests: XCTestCase {
    func testRenderCostAccountsForTextAndAttachmentImages() {
        XCTAssertEqual(
            BiliEmoteCacheBudget.renderCost(
                textLength: 10,
                attachmentImageCost: 3_072
            ),
            3_392
        )
    }

    func testCacheBudgetsAreBoundedByCountAndDecodedBytes() {
        XCTAssertLessThanOrEqual(BiliEmoteCacheBudget.renderCountLimit, 240)
        XCTAssertLessThanOrEqual(BiliEmoteCacheBudget.renderCostLimit, 24 * 1024 * 1024)
        XCTAssertLessThanOrEqual(BiliEmoteCacheBudget.imageCountLimit, 160)
        XCTAssertLessThanOrEqual(BiliEmoteCacheBudget.imageCostLimit, 16 * 1024 * 1024)
    }
}
