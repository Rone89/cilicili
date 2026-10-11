import XCTest
@testable import bili

@MainActor
final class DynamicPGCCardTests: XCTestCase {
    func testExperimentDefaultsOffAndPersistsWithoutChangingOtherSettings() {
        let suite = "DynamicPGCCardTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LibraryStore(userDefaults: defaults)
        XCTAssertFalse(store.dynamicPGCCardExperimentEnabled)
        store.setFollowsSystemFontSize(false)
        store.setDynamicPGCCardExperimentEnabled(true)
        XCTAssertTrue(LibraryStore(userDefaults: defaults).dynamicPGCCardExperimentEnabled)
        store.setDynamicPGCCardExperimentEnabled(false)
        let restored = LibraryStore(userDefaults: defaults)
        XCTAssertFalse(restored.dynamicPGCCardExperimentEnabled)
        XCTAssertFalse(restored.followsSystemFontSize)
    }

    func testBothPGCTypesDecodeLossyIDsAndPreserveRealMetadata() throws {
        for type in ["DYNAMIC_TYPE_PGC", "DYNAMIC_TYPE_PGC_UNION"] {
            let item = try decode(type: type, pgc: #"{"epid":"101","season_id":100,"title":"第1集","cover":"//i0.hdslb.com/test.jpg","duration_text":"24:00","badge":{"text":"会员"},"stat":{"play":"1.2万","danmaku":33}}"#)
            let pgc = try XCTUnwrap(item.pgc)
            XCTAssertEqual(pgc.episodeID, 101)
            XCTAssertEqual(pgc.seasonID, 100)
            XCTAssertEqual(pgc.playText, "1.2万")
            XCTAssertEqual(pgc.danmakuText, "33")
            XCTAssertEqual(pgc.badgeText, "会员")
            XCTAssertEqual(pgc.durationText, "24:00")
            XCTAssertEqual(pgc.cover, "https://i0.hdslb.com/test.jpg")
            XCTAssertEqual(pgc.playbackRoute?.episodeID, 101)
        }
    }

    func testDisabledPresentationRetainsFallbackWhileEnabledAvoidsDuplicateCoverAndTitle() throws {
        let item = try decode(pgc: #"{"title":"第1集","cover":"https://i0.hdslb.com/test.jpg","epid":101}"#)
        let old = DynamicFeedCardDisplayModel(item: item)
        let enabled = DynamicFeedCardDisplayModel(item: item, pgcEnabled: true)
        XCTAssertNil(old.pgc)
        XCTAssertEqual(old.topLevelDisplayText, "第1集")
        XCTAssertEqual(old.imageItems.count, 1)
        XCTAssertNotNil(enabled.pgc)
        XCTAssertTrue(enabled.imageItems.isEmpty)
        XCTAssertNil(enabled.topLevelDisplayText)
        XCTAssertFalse(enabled.usesSeparatedDynamicLayout)
        XCTAssertFalse(enabled.usesHomeVideoCardStyle)
        XCTAssertFalse(enabled.supportsDetailNavigation)
        XCTAssertEqual(item.commentOID, "777")
        XCTAssertEqual(item.commentType, 17)
        XCTAssertEqual(enabled.commentTitle, old.commentTitle)
        XCTAssertEqual(enabled.shareURL, old.shareURL)
        XCTAssertFalse(DynamicFeedKind.video.includes(item))
        XCTAssertTrue(DynamicFeedKind.all.includes(item))
    }

    func testBodyDescriptionIsKeptAndCoverRemovalRetainsOtherPictures() throws {
        let item = try decode(pgc: #"{"title":"第1集","epid":101,"cover":"https://i0.hdslb.com/test.jpg"}"#, desc: #"{"text":"更新啦"}"#)
        let enabled = DynamicFeedCardDisplayModel(item: item, pgcEnabled: true)
        XCTAssertEqual(enabled.topLevelDisplayText, "更新啦")
        let images = try JSONDecoder.bili.decode([DynamicImageItem].self, from: Data(#"[{"src":"https://i0.hdslb.com/test.jpg@200w.webp"},{"src":"https://i0.hdslb.com/other.jpg"}]"#.utf8))
        XCTAssertEqual(item.pgc?.bodyImages(from: images).map(\.url), ["https://i0.hdslb.com/other.jpg"])
    }

    func testURLsResolveOnlyCanonicalBilibiliEpisodeOrSeasonPaths() throws {
        let cases: [(String, Int?, Int?)] = [
            ("//www.bilibili.com/bangumi/play/ep101?from=dynamic", 101, nil),
            ("https://m.bilibili.com/bangumi/play/ss100", nil, 100),
            ("https://bilibili.com.evil.example/bangumi/play/ep101", nil, nil),
            ("https://example.com/bangumi/play/ep101", nil, nil),
            ("https://www.bilibili.com/bangumi/play/ep0", nil, nil),
            ("https://www.bilibili.com/bangumi/play/ep101extra", nil, nil)
        ]
        for (url, ep, season) in cases {
            let item = try decode(pgc: "{\"title\":\"番剧\",\"jump_url\":\"\(url)\"}")
            XCTAssertEqual(item.pgc?.episodeID, ep, url)
            XCTAssertEqual(item.pgc?.seasonID, season, url)
        }
    }

    func testInvalidIdentityNeverGuessesEpisodeFromAidOrId() throws {
        let pgc = try XCTUnwrap(decode(pgc: #"{"title":"番剧","epid":-1,"season_id":0,"id":101,"aid":101,"stat":{"play":null,"danmaku":false}}"#).pgc)
        XCTAssertNil(pgc.episodeID)
        XCTAssertNil(pgc.seasonID)
        XCTAssertNil(pgc.playbackRoute)
        XCTAssertNil(pgc.playText)
        XCTAssertNil(pgc.danmakuText)
        let booleans = try decode(pgc: #"{"title":"番剧","epid":true,"season_id":false}"#)
        XCTAssertNil(booleans.pgc?.playbackRoute)
    }

    func testMalformedPGCDoesNotBreakFeedOrCreateEmptyCard() throws {
        for payload in ["null", "[]", "{}", "{\"unknown\":true}"] {
            let item = try decode(pgc: payload, desc: #"{"text":"正文"}"#)
            XCTAssertNil(item.pgc, payload)
            XCTAssertEqual(DynamicFeedCardDisplayModel(item: item, pgcEnabled: true).topLevelDisplayText, "正文")
        }
    }

    func testWordMentioningBangumiDoesNotBecomePGCCard() throws {
        let item = try decode(type: "DYNAMIC_TYPE_WORD", pgc: #"{"epid":101,"title":"追番"}"#, desc: #"{"text":"今天追番"}"#)
        XCTAssertNil(item.pgc)
        XCTAssertNil(DynamicFeedCardDisplayModel(item: item, pgcEnabled: true).pgc)
    }

    func testForwardOriginalUsesSamePGCIdentity() throws {
        let item = try decode(pgc: #"{"epid":101,"season_id":100,"title":"第1集"}"#)
        let original = Self.json(type: "DYNAMIC_TYPE_PGC_UNION", pgc: #"{"epid":101,"season_id":100,"title":"第1集"}"#, desc: "null")
        let json = "{\"id_str\":\"888888\",\"type\":\"DYNAMIC_TYPE_FORWARD\",\"orig\":\(original)}"
        let forward = try JSONDecoder.bili.decode(DynamicFeedItem.self, from: Data(json.utf8))
        XCTAssertNil(forward.pgc)
        XCTAssertEqual(forward.original?.pgc, item.pgc)
        XCTAssertTrue(DynamicFeedCardDisplayModel(item: forward, pgcEnabled: true).usesSeparatedDynamicLayout)
    }

    private func decode(type: String = "DYNAMIC_TYPE_PGC_UNION", pgc: String, desc: String = "null") throws -> DynamicFeedItem {
        try JSONDecoder.bili.decode(DynamicFeedItem.self, from: Data(Self.json(type: type, pgc: pgc, desc: desc).utf8))
    }

    private static func json(type: String, pgc: String, desc: String) -> String {
        "{\"id_str\":\"123456789\",\"type\":\"\(type)\",\"basic\":{\"comment_id_str\":\"777\",\"comment_type\":17},\"modules\":{\"module_dynamic\":{\"desc\":\(desc),\"major\":{\"pgc\":\(pgc)}}}}"
    }
}
