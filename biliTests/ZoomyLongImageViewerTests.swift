import XCTest
import UIKit
@testable import bili

final class ZoomyLongImageViewerTests: XCTestCase {
    @MainActor
    func testEnhancedPreviewRequestsBoundedCDNImageAndOriginalHasSeparateCacheKey() throws {
        let original = try XCTUnwrap(URL(string: "https://i0.hdslb.com/bfs/new_dyn/example.jpg"))
        let item = ZoomyImagePreviewItem(id: "large", viewerURL: original,
                                        originalPixelSize: CGSize(width: 4032, height: 3024))
        let preview = try XCTUnwrap(item.loadingURL(targetPixelSize: 2400, enhancedLoadingEnabled: true))
        XCTAssertEqual(preview.absoluteString,
                       original.absoluteString + "@2400w_2400h_0e.webp")
        XCTAssertEqual(item.loadingURL(targetPixelSize: 2400, enhancedLoadingEnabled: true,
                                       requestsOriginal: true), original)
        XCTAssertEqual(item.loadingURL(targetPixelSize: 2400, enhancedLoadingEnabled: false), original)
        XCTAssertNotEqual(preview.absoluteString.biliImageCacheIdentityURLString(),
                          original.absoluteString.biliImageCacheIdentityURLString())
    }

    @MainActor
    func testSmallOriginalBypassesCDNResize() throws {
        let original = try XCTUnwrap(URL(string: "https://i0.hdslb.com/bfs/new_dyn/example.jpg"))
        for size in [CGSize(width: 2400, height: 1600), CGSize(width: 1080, height: 1920)] {
            let item = ZoomyImagePreviewItem(id: "small", viewerURL: original, originalPixelSize: size)
            XCTAssertEqual(item.loadingURL(targetPixelSize: 2400, enhancedLoadingEnabled: true), original)
            XCTAssertFalse(ZoomyViewerImageSizing.shouldOfferOriginalUpgrade(
                sourcePixelSize: item.originalPixelSize, baseTargetPixelSize: 2400))
        }
    }

    @MainActor
    func testUnknownDimensionsStillAllowOriginalUpgrade() throws {
        let item = ZoomyImagePreviewItem(id: "unknown",
            viewerURL: URL(string: "https://i0.hdslb.com/bfs/new_dyn/example.jpg"),
            originalPixelSize: CGSize(width: 0, height: 0))
        XCTAssertNil(item.originalPixelSize)
        XCTAssertNotEqual(item.loadingURL(targetPixelSize: 2400, enhancedLoadingEnabled: true), item.displayURL)
        XCTAssertTrue(ZoomyViewerImageSizing.shouldOfferOriginalUpgrade(
            sourcePixelSize: item.originalPixelSize, baseTargetPixelSize: 2400))
    }

    @MainActor
    func testAnimatedAndExternalImagesKeepTheirOriginalURL() throws {
        let gif = ZoomyImagePreviewItem(id: "gif",
            viewerURL: URL(string: "https://i0.hdslb.com/bfs/new_dyn/example.gif"))
        let live = ZoomyImagePreviewItem(id: "live",
            viewerURL: URL(string: "https://i0.hdslb.com/bfs/new_dyn/example.jpg"),
            liveVideoURL: URL(string: "https://example.com/live.mov"))
        let external = ZoomyImagePreviewItem(id: "external",
            viewerURL: URL(string: "https://example.com/hdslb.com/photo.jpg?token=value"))
        for item in [gif, live, external] {
            XCTAssertEqual(item.loadingURL(targetPixelSize: 2400, enhancedLoadingEnabled: true), item.displayURL)
        }
    }

    @MainActor
    func testDynamicImageMetadataReachesBothPreviewLayouts() throws {
        let image = try JSONDecoder().decode(DynamicImageItem.self,
            from: Data(#"{"src":"https://i0.hdslb.com/bfs/new_dyn/example.jpg","width":4032,"height":3024}"#.utf8))
        let expected = CGSize(width: 4032, height: 3024)
        XCTAssertEqual(DynamicImageDisplayItems.previewItems(
            from: DynamicImageDisplayItems.make(from: [image])).first?.originalPixelSize, expected)
        XCTAssertEqual(CompactDynamicImageDisplayItems.previewItems(
            from: CompactDynamicImageDisplayItems.make(from: [image])).first?.originalPixelSize, expected)
    }

    @MainActor
    func testOriginalUpgradeUsesSourceLongestSide() {
        for size in [CGSize(width: 2400, height: 1600), CGSize(width: 1080, height: 1920),
                     CGSize(width: 1600, height: 2400)] {
            XCTAssertFalse(ZoomyViewerImageSizing.shouldOfferOriginalUpgrade(
                sourcePixelSize: size, baseTargetPixelSize: 2400))
        }
        XCTAssertTrue(ZoomyViewerImageSizing.shouldOfferOriginalUpgrade(
            sourcePixelSize: CGSize(width: 1600, height: 2401), baseTargetPixelSize: 2400))
        XCTAssertTrue(ZoomyViewerImageSizing.shouldOfferOriginalUpgrade(
            sourcePixelSize: nil, baseTargetPixelSize: 2400))
    }

    @MainActor
    func testSourceDimensionsSurviveDownsampling() throws {
        let original = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 1500),
            format: {
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                return format
            }()).image { context in
                UIColor.red.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 3000, height: 1500))
            }
        let data = try XCTUnwrap(original.pngData())
        XCTAssertEqual(UIImage.sourcePixelSize(data: data), CGSize(width: 3000, height: 1500))
        let decoded = try XCTUnwrap(UIImage.downsampledImage(data: data, scale: 1, targetPixelSize: 2400))
        XCTAssertLessThanOrEqual(try XCTUnwrap(decoded.cgImage).width, 2400)
        XCTAssertNil(UIImage.sourcePixelSize(data: Data()))
    }

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
    func testEnhancedDismissScaleIsSubtleAndBounded() {
        XCTAssertEqual(
            ZoomyViewerInteractionPolicy.dismissScale(translationY: 0),
            1,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ZoomyViewerInteractionPolicy.dismissScale(translationY: 260),
            0.88,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ZoomyViewerInteractionPolicy.dismissScale(translationY: 520),
            0.88,
            accuracy: 0.001
        )
    }

    @MainActor
    func testEnhancedViewerRetainsSelectedPageAndImmediateNeighbors() {
        XCTAssertEqual(
            ZoomyViewerInteractionPolicy.retainedPageIndices(pageCount: 5, selectedIndex: 2),
            Set([1, 2, 3])
        )
        XCTAssertEqual(
            ZoomyViewerInteractionPolicy.retainedPageIndices(pageCount: 5, selectedIndex: 0),
            Set([0, 1])
        )
        XCTAssertEqual(
            ZoomyViewerInteractionPolicy.retainedPageIndices(pageCount: 5, selectedIndex: 4),
            Set([3, 4])
        )
    }

    @MainActor
    func testEnhancedViewerUsesNumericIndicatorOnlyForLargeGalleries() {
        XCTAssertFalse(ZoomyViewerInteractionPolicy.usesNumericPageIndicator(pageCount: 10))
        XCTAssertTrue(ZoomyViewerInteractionPolicy.usesNumericPageIndicator(pageCount: 11))
    }

    @MainActor
    func testLongImageDismissRequiresExperimentAndTopEdge() {
        XCTAssertFalse(
            ZoomyViewerInteractionPolicy.canBeginDismiss(
                usesLongImageScrolling: true,
                zoomScale: 1,
                minimumZoomScale: 1,
                contentOffsetY: 0,
                topContentInset: 0,
                enhancedInteractionEnabled: false
            )
        )
        XCTAssertTrue(
            ZoomyViewerInteractionPolicy.canBeginDismiss(
                usesLongImageScrolling: true,
                zoomScale: 1,
                minimumZoomScale: 1,
                contentOffsetY: 0,
                topContentInset: 0,
                enhancedInteractionEnabled: true
            )
        )
        XCTAssertFalse(
            ZoomyViewerInteractionPolicy.canBeginDismiss(
                usesLongImageScrolling: true,
                zoomScale: 1,
                minimumZoomScale: 1,
                contentOffsetY: 80,
                topContentInset: 0,
                enhancedInteractionEnabled: true
            )
        )
        XCTAssertFalse(
            ZoomyViewerInteractionPolicy.canBeginDismiss(
                usesLongImageScrolling: true,
                zoomScale: 2,
                minimumZoomScale: 1,
                contentOffsetY: 0,
                topContentInset: 0,
                enhancedInteractionEnabled: true
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
    func testViewerImageRetentionCanKeepNeighborTrio() {
        let group = ZoomyImagePreviewGroup()
        let previousImage = makeImage(size: CGSize(width: 400, height: 300))
        let currentImage = makeImage(size: CGSize(width: 500, height: 300))
        let nextImage = makeImage(size: CGSize(width: 600, height: 300))
        let distantImage = makeImage(size: CGSize(width: 700, height: 300))

        group.setImage(previousImage, for: "previous", quality: .viewer)
        group.setImage(currentImage, for: "current", quality: .viewer)
        group.setImage(nextImage, for: "next", quality: .viewer)
        group.setImage(distantImage, for: "distant", quality: .viewer)

        group.releaseViewerImages(except: Set(["previous", "current", "next"]))

        XCTAssertTrue(group.image(for: "previous") === previousImage)
        XCTAssertTrue(group.image(for: "current") === currentImage)
        XCTAssertTrue(group.image(for: "next") === nextImage)
        XCTAssertNil(group.image(for: "distant"))
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

    @MainActor
    func testOriginalViewerTargetUsesSourceLikeResolutionWithinMemoryBudget() {
        XCTAssertEqual(
            ZoomyViewerImageSizing.originalTargetPixelSize(widthToHeightAspectRatio: 4.0 / 3.0),
            5_656
        )
        XCTAssertEqual(
            ZoomyViewerImageSizing.originalTargetPixelSize(widthToHeightAspectRatio: 3.0 / 4.0),
            5_656
        )
        XCTAssertEqual(
            ZoomyViewerImageSizing.originalTargetPixelSize(widthToHeightAspectRatio: 0.1),
            15_491
        )
        XCTAssertEqual(
            ZoomyViewerImageSizing.originalTargetPixelSize(widthToHeightAspectRatio: nil),
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
