import XCTest
import UIKit
@testable import bili

final class ZoomyLongImageViewerTests: XCTestCase {
    @MainActor
    func testSharperCurrentImageIsNotReplacedBySmallerSameAspectImage() {
        XCTAssertTrue(
            ZoomyViewerImageQuality.shouldKeepCurrent(
                currentPixelSize: CGSize(width: 4_000, height: 3_000),
                candidatePixelSize: CGSize(width: 2_400, height: 1_800)
            )
        )
        XCTAssertFalse(
            ZoomyViewerImageQuality.shouldKeepCurrent(
                currentPixelSize: CGSize(width: 2_400, height: 1_800),
                candidatePixelSize: CGSize(width: 4_000, height: 3_000)
            )
        )
    }

    @MainActor
    func testDifferentAspectRatioCanReplaceCurrentImage() {
        XCTAssertFalse(
            ZoomyViewerImageQuality.shouldKeepCurrent(
                currentPixelSize: CGSize(width: 4_000, height: 3_000),
                candidatePixelSize: CGSize(width: 2_400, height: 1_200)
            )
        )
    }

    @MainActor
    func testDismissGestureRequiresDownwardVerticalPullAndDistance() {
        XCTAssertTrue(
            ZoomyViewerDismissGesturePolicy.isDownwardVerticalPull(
                CGSize(width: 20, height: 80)
            )
        )
        XCTAssertFalse(
            ZoomyViewerDismissGesturePolicy.isDownwardVerticalPull(
                CGSize(width: 80, height: 20)
            )
        )
        XCTAssertTrue(
            ZoomyViewerDismissGesturePolicy.shouldDismiss(
                translationY: 90,
                velocityY: 800
            )
        )
        XCTAssertFalse(
            ZoomyViewerDismissGesturePolicy.shouldDismiss(
                translationY: 90,
                velocityY: 400
            )
        )
    }

    @MainActor
    func testViewerImageIsNotReplacedByLateThumbnail() {
        let group = ZoomyImagePreviewGroup()
        let viewerImage = makeImage(size: CGSize(width: 400, height: 300))
        let thumbnailImage = makeImage(size: CGSize(width: 100, height: 75))

        group.setImage(viewerImage, for: "item", quality: .viewer)
        group.setImage(thumbnailImage, for: "item", quality: .thumbnail)

        XCTAssertTrue(group.image(for: "item") === viewerImage)
    }

    @MainActor
    func testViewerUsesOriginalBiliImageURL() throws {
        let transformedURL = try XCTUnwrap(
            URL(string: "https://i0.hdslb.com/bfs/new_dyn/example.jpg@672w_378h_1c.webp")
        )
        let item = ZoomyImagePreviewItem(id: "item", viewerURL: transformedURL)

        XCTAssertEqual(
            item.displayURL?.absoluteString,
            "https://i0.hdslb.com/bfs/new_dyn/example.jpg"
        )
    }

    @MainActor
    func testViewerUsesOriginalBiliImageURLWhenTransformIsInQuery() throws {
        let transformedURL = try XCTUnwrap(
            URL(string: "https://i0.hdslb.com/bfs/new_dyn/example.jpg?imageView2/2/w/672/format/webp")
        )
        let item = ZoomyImagePreviewItem(id: "item", viewerURL: transformedURL)

        XCTAssertEqual(
            item.displayURL?.absoluteString,
            "https://i0.hdslb.com/bfs/new_dyn/example.jpg"
        )
    }

    @MainActor
    func testLongImageStartsAtReadableScreenWidth() {
        let layout = ZoomyViewerImageSizing.initialLayout(
            imageSize: CGSize(width: 500, height: 5_000),
            boundsSize: CGSize(width: 390, height: 844)
        )

        XCTAssertTrue(layout.usesLongImageScrolling)
        XCTAssertEqual(layout.contentSize.width, 390, accuracy: 0.001)
        XCTAssertEqual(layout.contentSize.height, 3_900, accuracy: 0.001)
    }

    @MainActor
    func testRegularImageKeepsAspectFitLayout() {
        let layout = ZoomyViewerImageSizing.initialLayout(
            imageSize: CGSize(width: 1_200, height: 800),
            boundsSize: CGSize(width: 390, height: 844)
        )

        XCTAssertFalse(layout.usesLongImageScrolling)
        XCTAssertEqual(layout.contentSize.width, 390, accuracy: 0.001)
        XCTAssertEqual(layout.contentSize.height, 260, accuracy: 0.001)
    }

    @MainActor
    func testImageAtLongImageThresholdKeepsAspectFitLayout() {
        let layout = ZoomyViewerImageSizing.initialLayout(
            imageSize: CGSize(width: 1_000, height: 2_600),
            boundsSize: CGSize(width: 390, height: 844)
        )

        XCTAssertFalse(layout.usesLongImageScrolling)
        XCTAssertEqual(layout.contentSize.width, 324.615, accuracy: 0.001)
        XCTAssertEqual(layout.contentSize.height, 844, accuracy: 0.001)
    }

    @MainActor
    func testLongImageUsesLargerButBoundedDecodeTarget() {
        let target = ZoomyViewerImageSizing.targetPixelSize(
            baseTargetPixelSize: 2_400,
            widthToHeightAspectRatio: 0.1
        )

        XCTAssertGreaterThan(target, 2_400)
        XCTAssertLessThanOrEqual(target, 16_000)
        XCTAssertEqual(
            ZoomyViewerImageSizing.targetPixelSize(
                baseTargetPixelSize: 2_400,
                widthToHeightAspectRatio: 1.5
            ),
            2_400
        )
    }

    @MainActor
    func testHighQualityViewerDecodeBypassesThumbnailLongestSideCap() {
        let environment = PlaybackEnvironment(
            networkClass: .wifi,
            isLowPowerModeEnabled: false,
            isThermallyConstrained: false,
            thermalPressure: .nominal
        )
        let requestedTarget = ZoomyViewerImageSizing.targetPixelSize(
            baseTargetPixelSize: 2_400,
            widthToHeightAspectRatio: 0.1
        )

        XCTAssertEqual(
            RemoteImageDecodeSizing.effectiveTargetPixelSize(
                requestedTarget,
                scale: 1,
                policy: .standard,
                environment: environment
            ),
            2_600
        )
        XCTAssertEqual(
            RemoteImageDecodeSizing.effectiveTargetPixelSize(
                requestedTarget,
                scale: 1,
                policy: .highQualityViewer,
                environment: environment
            ),
            requestedTarget
        )
        XCTAssertEqual(
            RemoteImageDecodeSizing.effectiveTargetPixelSize(
                20_000,
                scale: 1,
                policy: .highQualityViewer,
                environment: environment
            ),
            RemoteImageDecodeSizing.highQualityViewerMaximumPixelSize
        )
    }

    private func makeImage(size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
