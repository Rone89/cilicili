import XCTest
@testable import bili

final class DynamicImagePrefetchSizingTests: XCTestCase {
    func testSingleImagePrefetchMatchesExpandedThumbnailRequest() {
        let request = DynamicImageThumbnailSizing.prefetchRequest(
            for: image(),
            imageCount: 1,
            usesCompactImages: false
        )

        XCTAssertEqual(request?.targetPixelSize, 1280)
        XCTAssertTrue(request?.source.url.absoluteString.contains("/w/1280/") == true)
    }

    func testGridImagePrefetchMatchesCompactThumbnailRequest() {
        let request = DynamicImageThumbnailSizing.prefetchRequest(
            for: image(),
            imageCount: 4,
            usesCompactImages: false
        )

        XCTAssertEqual(request?.targetPixelSize, 420)
        XCTAssertTrue(request?.source.url.absoluteString.contains("/w/420/") == true)
    }

    func testConservativeImagePrefetchUsesReducedTargets() {
        XCTAssertEqual(
            DynamicImageThumbnailSizing.targetPixelSize(
                usesExpandedImage: true,
                usesCompactImages: true
            ),
            960
        )
        XCTAssertEqual(
            DynamicImageThumbnailSizing.targetPixelSize(
                usesExpandedImage: false,
                usesCompactImages: true
            ),
            360
        )
    }

    private func image() -> DynamicImageItem {
        DynamicImageItem(
            url: "https://i0.hdslb.com/bfs/archive/example.jpg",
            width: 1600,
            height: 900,
            size: nil
        )
    }

    func testDynamicImageDecodesGIFMetadataAndViewerURL() throws {
        let data = """
        {
            "url": "https://i0.hdslb.com/bfs/dynamic/preview.jpg",
            "width": 640,
            "height": 360,
            "is_gif": true,
            "gif_url": "https://i0.hdslb.com/bfs/dynamic/animation.gif"
        }
        """.data(using: .utf8)!

        let image = try JSONDecoder().decode(DynamicImageItem.self, from: data)

        XCTAssertTrue(image.isAnimatedGIF)
        XCTAssertEqual(image.mediaBadgeText, "GIF")
        XCTAssertEqual(image.normalizedAnimatedImageURL, "https://i0.hdslb.com/bfs/dynamic/animation.gif")
    }

    func testDynamicImageDecodesLivePhotoObject() throws {
        let data = """
        {
            "url": "https://i0.hdslb.com/bfs/dynamic/live.jpg",
            "width": 1080,
            "height": 1920,
            "live_photo": {
                "video_url": "//upos-sz-mirrorali.bilivideo.com/live.mov"
            }
        }
        """.data(using: .utf8)!

        let image = try JSONDecoder().decode(DynamicImageItem.self, from: data)

        XCTAssertTrue(image.isLiveImage)
        XCTAssertEqual(image.mediaBadgeText, "LIVE")
        XCTAssertEqual(image.normalizedLiveVideoURL, "https://upos-sz-mirrorali.bilivideo.com/live.mov")
        XCTAssertTrue(image.isLongImage)
    }
}

final class ZoomyAnimatedImageDecodeBudgetTests: XCTestCase {
    func testNormalBudgetCapsLargeViewerGIFs() {
        let budget = ZoomyAnimatedImageDecodeBudget.make(
            targetPixelSize: 2_400,
            isConstrained: false
        )

        XCTAssertEqual(budget.maximumFrameCount, 24)
        XCTAssertEqual(budget.maximumPixelSize, 1_280)
        XCTAssertEqual(budget.maximumDecodedPixels, 18_000_000)
    }

    func testConstrainedBudgetReducesGIFMemoryPressure() {
        let budget = ZoomyAnimatedImageDecodeBudget.make(
            targetPixelSize: 2_400,
            isConstrained: true
        )

        XCTAssertEqual(budget.maximumFrameCount, 14)
        XCTAssertEqual(budget.maximumPixelSize, 900)
        XCTAssertEqual(budget.maximumDecodedPixels, 9_000_000)
    }

    func testGIFSamplingSpansTheOriginalTimeline() {
        let budget = ZoomyAnimatedImageDecodeBudget.make(
            targetPixelSize: 2_400,
            isConstrained: false
        )
        let frameIndices = budget.sampledFrameIndices(frameCount: 65, maximumFrameCount: 8)

        XCTAssertEqual(frameIndices.count, 8)
        XCTAssertEqual(frameIndices.first, 0)
        XCTAssertEqual(frameIndices.last, 64)
        XCTAssertEqual(frameIndices, frameIndices.sorted())
        XCTAssertEqual(Set(frameIndices).count, frameIndices.count)
    }
}

final class RemoteImageDisplayCachePolicyTests: XCTestCase {
    func testTransientImagesDoNotRetainAnAdditionalDisplayCacheCopy() {
        XCTAssertFalse(RemoteImageDisplayCachePolicy.transient.retainsImage)
    }

    func testRetainedImagesKeepTheExistingDisplayCacheBehavior() {
        XCTAssertTrue(RemoteImageDisplayCachePolicy.retained.retainsImage)
    }
}
