import XCTest
@testable import bili

final class HomeFeedImagePrefetchPolicyTests: XCTestCase {
    @MainActor
    func testInitialPrefetchAdaptsToLayoutAndEnvironment() {
        XCTAssertEqual(
            HomeFeedImagePrefetchPolicy.initialPrefetchLimit(
                layout: .singleColumn,
                isConservative: false
            ),
            5
        )
        XCTAssertEqual(
            HomeFeedImagePrefetchPolicy.initialPrefetchLimit(
                layout: .doubleColumn,
                isConservative: false
            ),
            6
        )
        XCTAssertEqual(
            HomeFeedImagePrefetchPolicy.initialPrefetchLimit(
                layout: .doubleColumn,
                isConservative: true
            ),
            3
        )
    }

    @MainActor
    func testLookaheadStartsBeyondVisibleViewport() {
        XCTAssertEqual(
            HomeFeedImagePrefetchPolicy.lookaheadStartIndex(
                visibleIndex: 3,
                layout: .singleColumn
            ),
            6
        )
        XCTAssertEqual(
            HomeFeedImagePrefetchPolicy.lookaheadStartIndex(
                visibleIndex: 3,
                layout: .doubleColumn
            ),
            7
        )
    }

    @MainActor
    func testBorderedSingleColumnProfileMatchesRenderedCoverDimensions() throws {
        let profile = HomeFeedCoverPrefetchProfile.make(
            layout: .borderedSingleColumn,
            metrics: HomeFeedLayoutMetrics(mode: .borderedSingleColumn, containerWidth: 390),
            displayScale: 3
        )
        let source = try XCTUnwrap(profile.source(for: "https://i0.hdslb.com/bfs/archive/example.jpg"))

        XCTAssertEqual(profile.targetPixelSize, 432)
        XCTAssertTrue(source.url.absoluteString.contains("/w/432/h/272/"))
    }
}
