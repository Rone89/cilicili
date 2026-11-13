import XCTest
@testable import bili

/// Covers the hdslb resize-suffix URL builders and the unified image-clarity
/// preset. The CDN only honors the `@<w>w_<h>h[_<q>q].webp` suffix form; the
/// previously emitted `?imageView2/...` query form is ignored and returned
/// the untouched original. One preset drives both the size cap and the
/// compression digit.
final class RemoteImageURLClarityTests: XCTestCase {
    private let hdslbSource = "https://i0.hdslb.com/bfs/archive/088e084c6ddda75faeadf62af0c976f31434dab1.jpg"
    private let externalSource = "https://example.com/pictures/cover.jpg"

    override func setUp() {
        super.setUp()
        clearPreferenceKeys()
    }

    override func tearDown() {
        clearPreferenceKeys()
        super.tearDown()
    }

    private func clearPreferenceKeys() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: RemoteImageClarityPreset.storageKey)
        defaults.removeObject(forKey: RemoteImageQualityPreference.storageKey)
        defaults.removeObject(forKey: "cc.bili.display.coverClarityPreference.v1")
    }

    private func withPreset(_ preset: RemoteImageClarityPreset, _ body: () -> Void) {
        UserDefaults.standard.set(preset.rawValue, forKey: RemoteImageClarityPreset.storageKey)
        defer { UserDefaults.standard.removeObject(forKey: RemoteImageClarityPreset.storageKey) }
        body()
    }

    // MARK: Preset mapping

    func testQualityMappingMatchesBilibiliCDNDigits() {
        XCTAssertNil(RemoteImageClarityPreset.automatic.quality)
        XCTAssertEqual(RemoteImageClarityPreset.dataSaver.quality, 60)
        XCTAssertEqual(RemoteImageClarityPreset.high.quality, 90)
        XCTAssertEqual(RemoteImageClarityPreset.original.quality, 100)
    }

    func testSizePreferenceMapping() {
        XCTAssertEqual(RemoteImageClarityPreset.automatic.sizePreference, .automatic)
        XCTAssertEqual(RemoteImageClarityPreset.dataSaver.sizePreference, .dataSaver)
        XCTAssertEqual(RemoteImageClarityPreset.high.sizePreference, .high)
        XCTAssertEqual(RemoteImageClarityPreset.original.sizePreference, .high)
    }

    func testStoredFallsBackToAutomaticForUnknownRawValue() {
        UserDefaults.standard.set("bogus", forKey: RemoteImageClarityPreset.storageKey)
        XCTAssertEqual(RemoteImageClarityPreset.stored(), .automatic)
        UserDefaults.standard.removeObject(forKey: RemoteImageClarityPreset.storageKey)
        XCTAssertEqual(RemoteImageClarityPreset.stored(), RemoteImageClarityPreset.defaultValue)
    }

    func testMigrationFromLegacySizePreference() {
        let legacyKey = RemoteImageQualityPreference.storageKey
        UserDefaults.standard.set(RemoteImageQualityPreference.high.rawValue, forKey: legacyKey)
        XCTAssertEqual(RemoteImageClarityPreset.stored(), .high)
        UserDefaults.standard.set(RemoteImageQualityPreference.dataSaver.rawValue, forKey: legacyKey)
        XCTAssertEqual(RemoteImageClarityPreset.stored(), .dataSaver)
        UserDefaults.standard.set(RemoteImageQualityPreference.balanced.rawValue, forKey: legacyKey)
        XCTAssertEqual(RemoteImageClarityPreset.stored(), .automatic)
        UserDefaults.standard.removeObject(forKey: legacyKey)
        XCTAssertEqual(RemoteImageClarityPreset.stored(), .automatic)
    }

    func testUnifiedKeyTakesPrecedenceOverLegacy() {
        UserDefaults.standard.set(RemoteImageQualityPreference.dataSaver.rawValue, forKey: RemoteImageQualityPreference.storageKey)
        withPreset(.original) {
            XCTAssertEqual(RemoteImageClarityPreset.stored(), .original)
        }
    }

    // MARK: Resize suffix builders

    func testAutomaticOmitsQualityPiece() {
        withPreset(.automatic) {
            XCTAssertEqual(
                hdslbSource.biliCoverThumbnailURL(width: 480, height: 270),
                "https://i0.hdslb.com/bfs/archive/088e084c6ddda75faeadf62af0c976f31434dab1.jpg@480w_270h.webp"
            )
        }
    }

    func testPinnedQualityAppendsQualityPiece() {
        for (preset, digit) in [
            (RemoteImageClarityPreset.dataSaver, "60"),
            (RemoteImageClarityPreset.high, "90"),
            (RemoteImageClarityPreset.original, "100"),
        ] {
            withPreset(preset) {
                XCTAssertEqual(
                    hdslbSource.biliCoverThumbnailURL(width: 480, height: 270),
                    "https://i0.hdslb.com/bfs/archive/088e084c6ddda75faeadf62af0c976f31434dab1.jpg@480w_270h_\(digit)q.webp"
                )
            }
        }
    }

    func testWidthOnlyThumbnailUsesWidthSuffix() {
        withPreset(.dataSaver) {
            // 480 is below the dataSaver 560px cap, isolating the width-only suffix.
            XCTAssertEqual(
                hdslbSource.biliImageThumbnailURL(maxSide: 480),
                "https://i0.hdslb.com/bfs/archive/088e084c6ddda75faeadf62af0c976f31434dab1.jpg@480w_60q.webp"
            )
        }
    }

    func testDataSaverCapsCoverSize() {
        withPreset(.dataSaver) {
            // dataSaver caps the long side at 560px; a 960x540 request shrinks.
            let url = hdslbSource.biliCoverThumbnailURL(width: 960, height: 540)
            XCTAssertTrue(url.contains("@560w_315h"), url)
        }
    }

    func testExistingResizeSuffixIsReplaced() {
        withPreset(.high) {
            XCTAssertEqual(
                "https://i0.hdslb.com/bfs/archive/abc.jpg@1920w_1080h.webp".biliCoverThumbnailURL(width: 480, height: 270),
                "https://i0.hdslb.com/bfs/archive/abc.jpg@480w_270h_90q.webp"
            )
        }
    }

    func testNonHdslbURLIsLeftUntouched() {
        withPreset(.dataSaver) {
            XCTAssertEqual(externalSource.biliCoverThumbnailURL(width: 480, height: 270), externalSource)
            XCTAssertEqual(externalSource.biliImageThumbnailURL(maxSide: 640), externalSource)
        }
    }

    // MARK: Cache identity

    func testQualityChangeKeepsCacheIdentity() {
        let automatic = hdslbSource.biliCoverThumbnailURL(width: 480, height: 270).biliImageCacheIdentityURLString()
        withPreset(.original) {
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
