import XCTest
@testable import bili

/// Covers the hdslb resize-suffix URL builders and the cover-clarity
/// preference. The CDN only honors the `@<w>w_<h>h[_<q>q].webp` suffix form;
/// the previously emitted `?imageView2/...` query form is ignored and returned
/// the untouched original.
final class RemoteImageURLClarityTests: XCTestCase {
    private let hdslbSource = "https://i0.hdslb.com/bfs/archive/088e084c6ddda75faeadf62af0c976f31434dab1.jpg"
    private let externalSource = "https://example.com/pictures/cover.jpg"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: RemoteCoverClarityPreference.storageKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: RemoteCoverClarityPreference.storageKey)
        super.tearDown()
    }

    private func withClarity(_ preference: RemoteCoverClarityPreference, _ body: () -> Void) {
        UserDefaults.standard.set(preference.rawValue, forKey: RemoteCoverClarityPreference.storageKey)
        defer { UserDefaults.standard.removeObject(forKey: RemoteCoverClarityPreference.storageKey) }
        body()
    }

    // MARK: Preference mapping

    func testQualityMappingMatchesBilibiliCDNDigits() {
        XCTAssertNil(RemoteCoverClarityPreference.automatic.quality)
        XCTAssertEqual(RemoteCoverClarityPreference.smooth.quality, 60)
        XCTAssertEqual(RemoteCoverClarityPreference.standard.quality, 75)
        XCTAssertEqual(RemoteCoverClarityPreference.high.quality, 90)
        XCTAssertEqual(RemoteCoverClarityPreference.original.quality, 100)
    }

    func testStoredFallsBackToAutomaticForUnknownRawValue() {
        UserDefaults.standard.set("bogus", forKey: RemoteCoverClarityPreference.storageKey)
        XCTAssertEqual(RemoteCoverClarityPreference.stored(), .automatic)
        UserDefaults.standard.removeObject(forKey: RemoteCoverClarityPreference.storageKey)
        XCTAssertEqual(RemoteCoverClarityPreference.stored(), RemoteCoverClarityPreference.defaultValue)
    }

    // MARK: Resize suffix builders

    func testAutomaticOmitsQualityPiece() {
        withClarity(.automatic) {
            XCTAssertEqual(
                hdslbSource.biliCoverThumbnailURL(width: 480, height: 270),
                "https://i0.hdslb.com/bfs/archive/088e084c6ddda75faeadf62af0c976f31434dab1.jpg@480w_270h.webp"
            )
        }
    }

    func testPinnedQualityAppendsQualityPiece() {
        for (preference, digit) in [
            (RemoteCoverClarityPreference.smooth, "60"),
            (RemoteCoverClarityPreference.standard, "75"),
            (RemoteCoverClarityPreference.high, "90"),
            (RemoteCoverClarityPreference.original, "100"),
        ] {
            withClarity(preference) {
                XCTAssertEqual(
                    hdslbSource.biliCoverThumbnailURL(width: 480, height: 270),
                    "https://i0.hdslb.com/bfs/archive/088e084c6ddda75faeadf62af0c976f31434dab1.jpg@480w_270h_\(digit)q.webp"
                )
            }
        }
    }

    func testWidthOnlyThumbnailUsesWidthSuffix() {
        withClarity(.smooth) {
            XCTAssertEqual(
                hdslbSource.biliImageThumbnailURL(maxSide: 640),
                "https://i0.hdslb.com/bfs/archive/088e084c6ddda75faeadf62af0c976f31434dab1.jpg@640w_60q.webp"
            )
        }
    }

    func testExistingResizeSuffixIsReplaced() {
        withClarity(.high) {
            XCTAssertEqual(
                "https://i0.hdslb.com/bfs/archive/abc.jpg@1920w_1080h.webp".biliCoverThumbnailURL(width: 480, height: 270),
                "https://i0.hdslb.com/bfs/archive/abc.jpg@480w_270h_90q.webp"
            )
        }
    }

    func testNonHdslbURLIsLeftUntouched() {
        withClarity(.smooth) {
            XCTAssertEqual(externalSource.biliCoverThumbnailURL(width: 480, height: 270), externalSource)
            XCTAssertEqual(externalSource.biliImageThumbnailURL(maxSide: 640), externalSource)
        }
    }

    // MARK: Cache identity

    func testQualityChangeKeepsCacheIdentity() {
        let automatic = hdslbSource.biliCoverThumbnailURL(width: 480, height: 270).biliImageCacheIdentityURLString()
        withClarity(.original) {
            let original = hdslbSource.biliCoverThumbnailURL(width: 480, height: 270).biliImageCacheIdentityURLString()
            XCTAssertEqual(automatic, original)
        }
    }

    func testSizeChangeChangesCacheIdentity() {
        let small = hdslbSource.biliCoverThumbnailURL(width: 480, height: 270).biliImageCacheIdentityURLString()
        let large = hdslbSource.biliCoverThumbnailURL(width: 960, height: 540).biliImageCacheIdentityURLString()
        XCTAssertNotEqual(small, large)
    }

    func testLegacyImageView2IdentityStillParses() {
        let legacy = "\(hdslbSource)?imageView2/2/w/480/h/270/format/webp".biliImageCacheIdentityURLString()
        XCTAssertTrue(legacy.contains("#crop-"))
    }

    // MARK: DynamicPGC cover dedupe

    func testBodyImageDedupeComparesSourceAcrossVariants() throws {
        let pgcJSON = #"{"cover":"\#(hdslbSource)"}"#
        let model = try JSONDecoder().decode(DynamicPGC.self, from: Data(pgcJSON.utf8))
        let bodyImages = [
            DynamicImageItem(url: "\(hdslbSource)@480w_270h_60q.webp", width: nil, height: nil, size: nil),
            DynamicImageItem(url: "https://i0.hdslb.com/bfs/new_dyn/other.jpg", width: nil, height: nil, size: nil),
        ]
        let remaining = model.bodyImages(from: bodyImages)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.normalizedURL, "https://i0.hdslb.com/bfs/new_dyn/other.jpg")
    }
}
