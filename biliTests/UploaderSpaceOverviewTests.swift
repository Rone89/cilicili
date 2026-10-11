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
        XCTAssertEqual(overview.favorites?.items.first?.isPublic, true)
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

    func testMissingEmptyAndMalformedModulesRemainDistinct() throws {
        let missing = try decode(#"{"card":{"mid":1},"season":null}"#)
        XCTAssertFalse(missing.favoritesDecodingFailed)
        XCTAssertFalse(missing.bangumiDecodingFailed)
        XCTAssertNil(missing.favorites)
        let empty = try decode(#"{"card":{"mid":1},"favourite2":{"count":0,"item":[]},"season":{"count":0,"item":[]}}"#)
        XCTAssertEqual(empty.favorites?.items, [])
        XCTAssertFalse(empty.favoritesDecodingFailed)
        let malformed = try decode(#"{"card":{"mid":1},"favourite2":{"count":2},"season":"bad"}"#)
        XCTAssertTrue(malformed.favoritesDecodingFailed)
        XCTAssertTrue(malformed.bangumiDecodingFailed)
    }

    func testWebBangumiUsesSeasonIDAndDoesNotBecomeVideo() throws {
        let payload = try JSONDecoder.bili.decode(UploaderSpaceBangumiList.self, from: Data(#"{"total":5,"list":[{"season_id":777,"title":"追番","cover":"https://example.com/a.jpg"}]}"#.utf8))
        XCTAssertEqual(payload.total, 5)
        XCTAssertEqual(payload.list.first?.seasonID, 777)
        XCTAssertNil(payload.list.first?.video(defaultMID: 1))
        XCTAssertThrowsError(try JSONDecoder.bili.decode(UploaderSpaceBangumiList.self, from: Data(#"{"total":5}"#.utf8)))
    }

    func testOwnFavoritePreviewPreservesCountAndKnownPrivacy() throws {
        let folders = try JSONDecoder.bili.decode([FavoriteFolder].self, from: Data(#"[{"id":1,"title":"私密","attr":3,"media_count":12},{"id":2,"title":"未知"}]"#.utf8))
        let preview = UploaderSpaceFavoriteGroup(folders: folders)
        XCTAssertEqual(preview.count, 2)
        XCTAssertEqual(preview.items[0].count, 12)
        XCTAssertEqual(preview.items[0].isPublic, false)
        XCTAssertNil(preview.items[1].isPublic)
    }

    func testFavoriteNullListIsEmptyOnlyWithExplicitZeroCount() throws {
        let decoder = JSONDecoder.bili
        let empty = try decoder.decode(UploaderSpaceFavoriteList.self, from: Data(#"{"count":0,"list":null}"#.utf8))
        XCTAssertTrue(empty.list.isEmpty)
        for json in [#"{"list":null}"#, #"{"count":3,"list":null}"#, #"{"count":3,"list":[]}"#, #"{"count":0}"#] {
            XCTAssertThrowsError(try decoder.decode(UploaderSpaceFavoriteList.self, from: Data(json.utf8)))
        }
    }

    func testAPPFollowSentinelsAndFollowerDirectionAreNotFollowing() throws {
        for relation in [#"{"is_follow":-999,"is_followed":1}"#, #"{"is_followed":1}"#] {
            let overview = try decode("{\"card\":{\"mid\":1,\"relation\":\(relation)},\"following\":367,\"relation\":-999}")
            XCTAssertNil(overview.profile.following)
        }
        let unfollowed = try decode(#"{"card":{"mid":1,"relation":{"is_follow":0,"is_followed":1}},"relation":0}"#)
        XCTAssertEqual(unfollowed.profile.following, false)
        let followed = try decode(#"{"card":{"mid":1,"relation":{"is_follow":1,"status":2}},"relation":2}"#)
        XCTAssertEqual(followed.profile.following, true)
        let blocked = try decode(#"{"card":{"mid":1,"relation":{"is_follow":1}},"relation":-1}"#)
        XCTAssertEqual(blocked.profile.following, false)
    }

    func testAPPFavoriteUsesMediaIDAndPrivacyFlagHasAPPSemantics() throws {
        let overview = try decode(#"{"card":{"mid":1},"favourite2":{"item":[{"id":7,"media_id":7001,"is_public":0},{"id":8,"media_id":8001,"is_public":1},{"id":9,"is_public":-999}]}}"#)
        XCTAssertEqual(overview.favorites?.items[0].folder.id, 7001)
        XCTAssertEqual(overview.favorites?.items[0].isPublic, true)
        XCTAssertEqual(overview.favorites?.items[1].isPublic, false)
        XCTAssertNil(overview.favorites?.items[2].isPublic)
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
