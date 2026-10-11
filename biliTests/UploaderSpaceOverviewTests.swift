import XCTest
@testable import bili

final class UploaderSpaceOverviewTests: XCTestCase {
    func testRealSpaceMetadataAndPreviewRouting() throws {
        let overview = try decode(#"""
        {"card":{"mid":"123","name":"测试用户","fans":29,"attention":367,
        "level_info":{"current_level":6},"vip":{"status":1,"label":{"text":"年度大会员"}},
        "official_verify":{"type":0,"desc":"认证信息"},"space_tag":[{"type":"location","title":"广东"}]},
        "images":{"imgUrl":"https://example.com/day.jpg","night_imgurl":"https://example.com/night.jpg"},
        "tab2":[{"param":"home"},{"param":"archive"}],
        "archive":{"count":"3","item":[{"param":"88","title":"投稿","goto":"av"}]},
        "like_archive":{"count":296,"item":[{"param":"99","title":"点赞","author":"真正作者","goto":"av"}]},
        "coin_archive":{"count":2,"item":[]},
        "favourite2":{"count":84,"item":[{"id":9,"title":"默认收藏夹","count":221,"is_public":0}]},
        "season":{"count":5,"item":[{"param":"777","title":"追番","goto":"bangumi","is_pgc":1}]},
        "setting":{"fav_video":0,"likes_video":1,"coins_video":0,"bangumi":0}}
        """#)
        XCTAssertEqual(overview.profile.card?.mid, 123)
        XCTAssertEqual(overview.level, 6)
        XCTAssertEqual(overview.vipLabel, "年度大会员")
        XCTAssertEqual(overview.verification, "认证信息")
        XCTAssertEqual(overview.location, "广东")
        XCTAssertEqual(overview.availableTabIDs, ["home", "archive"])
        XCTAssertEqual(overview.archive?.items.first?.video(defaultMID: 123)?.aid, 88)
        XCTAssertEqual(overview.likes?.items.first?.video(defaultMID: 0)?.owner?.mid, 0)
        XCTAssertEqual(overview.likes?.items.first?.video(defaultMID: 0)?.owner?.name, "真正作者")
        XCTAssertEqual(overview.favorites?.items.first?.count, 221)
        XCTAssertEqual(overview.favorites?.items.first?.isPublic, false)
        XCTAssertEqual(overview.bangumi?.items.first?.seasonID, 777)
        XCTAssertNil(overview.bangumi?.items.first?.video(defaultMID: 123))
        XCTAssertEqual(overview.privacy?.favoritesVisible, false)
        XCTAssertEqual(overview.privacy?.likesVisible, true)
    }

    func testMissingPrivacyAndMalformedOptionalModuleDoNotHideOtherContent() throws {
        let overview = try decode(#"{"card":{"mid":123,"name":"公开用户"},"archive":"bad module","like_archive":{"item":[{"param":"99","goto":"av","title":"视频"}]}}"#)
        XCTAssertEqual(overview.profile.card?.name, "公开用户")
        XCTAssertNil(overview.archive)
        XCTAssertNil(overview.privacy)
        XCTAssertEqual(overview.likes?.items.count, 1)
        XCTAssertTrue(overview.hasPreviewContent)
        XCTAssertNil(overview.level)
    }

    func testUnknownCardTypesNeverBecomeVideoRoutes() throws {
        let overview = try decode(#"{"card":{"mid":1},"archive":{"item":[{"param":"7","goto":"article"},{"param":"8","goto":"live"},{"title":"缺少标识"}]},"season":{"item":[{"param":"0","goto":"bangumi"}]}}"#)
        XCTAssertTrue(overview.archive!.items.allSatisfy { $0.video(defaultMID: 1) == nil })
        XCTAssertNil(overview.bangumi?.items.first?.seasonID)
        XCTAssertFalse(overview.hasPreviewContent)
    }

    func testSeasonModuleAllowsMissingGotoAndInvalidVIPIsNotShown() throws {
        let overview = try decode(#"{"card":{"mid":1,"vip":{"status":0,"label":{"text":"已失效"}}},"season":{"item":[{"param":"777","title":"追番"}]}}"#)
        XCTAssertNil(overview.vipLabel)
        XCTAssertEqual(overview.bangumi?.items.first?.seasonID, 777)
        XCTAssertTrue(overview.hasPreviewContent)
    }

    @MainActor
    func testExperimentDefaultsOffAndPersistsWithoutTouchingOtherSettings() throws {
        let suite = "UploaderSpaceOverviewTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LibraryStore(userDefaults: defaults)
        XCTAssertFalse(store.personalSpaceEnhancementExperimentEnabled)
        store.setPersonalSpaceEnhancementExperimentEnabled(true)
        XCTAssertTrue(LibraryStore(userDefaults: defaults).personalSpaceEnhancementExperimentEnabled)
        store.setPersonalSpaceEnhancementExperimentEnabled(false)
        XCTAssertFalse(LibraryStore(userDefaults: defaults).personalSpaceEnhancementExperimentEnabled)
    }

    private func decode(_ json: String) throws -> UploaderSpaceOverview {
        try JSONDecoder.bili.decode(UploaderSpaceOverview.self, from: Data(json.utf8))
    }
}
