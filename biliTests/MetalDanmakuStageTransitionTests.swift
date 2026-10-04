import XCTest
@testable import bili

final class MetalDanmakuStageTransitionTests: XCTestCase {
    func testAspectFitMapsLogicalStageIntoTargetWithoutStretching() {
        let transform = MetalDanmakuStageTransform.aspectFit(
            from: CGSize(width: 900, height: 500),
            into: CGSize(width: 500, height: 900)
        )

        XCTAssertEqual(transform.scale, 5.0 / 9.0, accuracy: 0.001)
        XCTAssertEqual(transform.translation.x, 0, accuracy: 0.001)
        XCTAssertEqual(transform.translation.y, (900 - 500.0 * 5.0 / 9.0) / 2, accuracy: 0.001)
        let mapped = transform.map(CGRect(x: 0, y: 0, width: 900, height: 500))
        XCTAssertEqual(mapped.origin.x, 0, accuracy: 0.001)
        XCTAssertEqual(mapped.origin.y, transform.translation.y, accuracy: 0.001)
        XCTAssertEqual(mapped.width, 500, accuracy: 0.001)
        XCTAssertEqual(mapped.height, 500.0 * 5.0 / 9.0, accuracy: 0.001)
    }

    func testVideoViewportUsesActualAspectFitRectAndPreservesOrigin() {
        let bounds = CGRect(x: 12, y: 24, width: 500, height: 900)
        let viewport = MetalDanmakuVideoViewport.aspectFit(in: bounds, aspectRatio: 16.0 / 9.0)

        XCTAssertEqual(viewport.minX, 12, accuracy: 0.001)
        XCTAssertEqual(viewport.minY, 24 + (900 - 500 / (16.0 / 9.0)) / 2, accuracy: 0.001)
        XCTAssertEqual(viewport.width, 500, accuracy: 0.001)
        XCTAssertEqual(viewport.height, 500 / (16.0 / 9.0), accuracy: 0.001)
    }

    func testUnknownOrInvalidVideoAspectFallsBackToBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 400)
        XCTAssertEqual(MetalDanmakuVideoViewport.aspectFit(in: bounds, aspectRatio: nil), bounds)
        XCTAssertEqual(MetalDanmakuVideoViewport.aspectFit(in: bounds, aspectRatio: .nan), bounds)
        XCTAssertEqual(MetalDanmakuVideoViewport.aspectFit(in: bounds, aspectRatio: 0), bounds)
    }
}
