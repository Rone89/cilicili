import XCTest
@testable import bili

@MainActor
final class VideoDetailSponsoredBadgeTests: XCTestCase {
    func testOnlyCommercialPromotionBitMarksVideoSponsored() throws {
        for value in [4096, 4097, 12288] {
            XCTAssertTrue(try decode(attribute: String(value)).isSponsored)
        }
        for value in [0, 4095, 8192, -1, -4096] {
            XCTAssertFalse(try decode(attribute: String(value)).isSponsored)
        }
    }

    func testMissingNullAndMalformedAttributeDoNotRejectDetail() throws {
        let attributes: [String?] = [nil, "null", "\"4096\"", "\"invalid\"", "true", "[]", "{}", "4096.5", "99999999999999999999999999"]
        for attribute in attributes {
            let video = try decode(attribute: attribute)
            XCTAssertEqual(video.title, "视频标题")
            XCTAssertNil(video.attribute)
            XCTAssertFalse(video.isSponsored)
        }
    }

    func testDetailMergeUsesAuthoritativeAttributeIncludingZeroAndMissing() throws {
        let preview = try decode(attribute: "4096")
        for attribute in ["0", "8192"] {
            XCTAssertFalse(preview.mergingFilledValues(from: try decode(attribute: attribute)).isSponsored)
        }
        XCTAssertFalse(preview.mergingFilledValues(from: try decode(attribute: nil)).isSponsored)
        let ordinary = try decode(attribute: nil)
        XCTAssertTrue(ordinary.mergingFilledValues(from: preview).isSponsored)
    }

    func testExperimentDefaultsOffAndPersistsExplicitChoice() {
        let suite = "sponsored-badge-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LibraryStore(userDefaults: defaults)
        XCTAssertFalse(store.videoDetailSponsoredBadgeExperimentEnabled)
        store.setVideoDetailSponsoredBadgeExperimentEnabled(true)
        XCTAssertTrue(LibraryStore(userDefaults: defaults).videoDetailSponsoredBadgeExperimentEnabled)
        store.setVideoDetailSponsoredBadgeExperimentEnabled(false)
        XCTAssertFalse(LibraryStore(userDefaults: defaults).videoDetailSponsoredBadgeExperimentEnabled)
    }

    func testRenderSnapshotUpdatesSponsoredStateWithoutChangingTitle() {
        let store = VideoDetailDescriptionRenderStore()
        var snapshot = VideoDetailDescriptionRenderSnapshot()
        snapshot.titleText = "视频标题"
        snapshot.isSponsored = true
        store.update(snapshot)
        XCTAssertTrue(store.isSponsored)
        snapshot.isSponsored = false
        store.update(snapshot)
        XCTAssertFalse(store.isSponsored)
        XCTAssertEqual(store.titleText, "视频标题")
    }

    private func decode(attribute: String?) throws -> VideoItem {
        let field = attribute.map { ",\"attribute\":\($0)" } ?? ""
        let json = "{\"bvid\":\"BV1badge\",\"title\":\"视频标题\"\(field)}"
        return try JSONDecoder().decode(VideoItem.self, from: Data(json.utf8))
    }
}
