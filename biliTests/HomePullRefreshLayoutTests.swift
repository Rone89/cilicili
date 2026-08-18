import XCTest
@testable import bili

final class HomePullRefreshLayoutTests: XCTestCase {
    func testRefreshingReservesStableTopInset() {
        XCTAssertEqual(
            HomePullRefreshLayout.topInset(isRefreshing: true),
            HomePullRefreshLayout.refreshingTopInset
        )
        XCTAssertEqual(HomePullRefreshLayout.refreshingTopInset, 52)
    }

    func testIdleLayoutDoesNotReserveSpace() {
        XCTAssertEqual(HomePullRefreshLayout.topInset(isRefreshing: false), 0)
    }
}
