import XCTest
@testable import bili

final class VideoRecommendationFilterTests: XCTestCase {
    func testInactiveConfigurationKeepsVideosInFeedAndRelated() {
        let videos = [
            video("BV1", title: "短视频", duration: 20, view: 10, like: 0),
            video("BV2", title: "正常视频", duration: 120, view: 1_000, like: 40)
        ]
        let configuration = VideoRecommendationFilterConfiguration(
            minimumDurationSeconds: 0,
            minimumViewCount: 0,
            minimumLikeRatioPercent: 0,
            blockedKeywords: [],
            appliesToRelatedVideos: false
        )

        XCTAssertEqual(
            VideoRecommendationFilter.filtered(videos, configuration: configuration, context: .feed),
            videos
        )
        XCTAssertEqual(
            VideoRecommendationFilter.filtered(videos, configuration: configuration, context: .related),
            videos
        )
    }

    func testFeedFiltersByDurationViewsLikeRatioAndTitleKeyword() {
        let videos = [
            video("BV1", title: "太短", duration: 30, view: 1_000, like: 50),
            video("BV2", title: "播放太低", duration: 120, view: 100, like: 50),
            video("BV3", title: "点赞太低", duration: 120, view: 1_000, like: 10),
            video("BV4", title: "广告合集", duration: 120, view: 1_000, like: 50),
            video("BV5", title: "保留", duration: 120, view: 1_000, like: 50)
        ]
        let configuration = VideoRecommendationFilterConfiguration(
            minimumDurationSeconds: 60,
            minimumViewCount: 500,
            minimumLikeRatioPercent: 2,
            blockedKeywords: ["广告"],
            appliesToRelatedVideos: false
        )

        XCTAssertEqual(
            VideoRecommendationFilter.filtered(videos, configuration: configuration, context: .feed).map(\.bvid),
            ["BV5"]
        )
    }

    func testRelatedFilteringRequiresRelatedToggle() {
        let videos = [
            video("BV1", title: "播放太低", duration: 120, view: 100, like: 50),
            video("BV2", title: "保留", duration: 120, view: 1_000, like: 50)
        ]
        let disabledConfiguration = VideoRecommendationFilterConfiguration(
            minimumDurationSeconds: 0,
            minimumViewCount: 500,
            minimumLikeRatioPercent: 0,
            blockedKeywords: [],
            appliesToRelatedVideos: false
        )
        let enabledConfiguration = VideoRecommendationFilterConfiguration(
            minimumDurationSeconds: 0,
            minimumViewCount: 500,
            minimumLikeRatioPercent: 0,
            blockedKeywords: [],
            appliesToRelatedVideos: true
        )

        XCTAssertEqual(
            VideoRecommendationFilter.filtered(videos, configuration: disabledConfiguration, context: .related).map(\.bvid),
            ["BV1", "BV2"]
        )
        XCTAssertEqual(
            VideoRecommendationFilter.filtered(videos, configuration: enabledConfiguration, context: .related).map(\.bvid),
            ["BV2"]
        )
    }

    @MainActor
    func testBlocksChargingVideosDefaultsToFalseAndPersists() {
        let suiteName = "VideoRecommendationFilterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = LibraryStore(userDefaults: defaults)
        XCTAssertFalse(store.blocksChargingVideos)

        store.setBlocksChargingVideos(true)
        XCTAssertTrue(store.blocksChargingVideos)
        XCTAssertTrue(LibraryStore(userDefaults: defaults).blocksChargingVideos)

        store.setBlocksChargingVideos(false)
        XCTAssertFalse(LibraryStore(userDefaults: defaults).blocksChargingVideos)
    }

    func testBlocksChargingVideosFiltersFeedAndRelatedWithoutFalsePositives() throws {
        let normalWithChargingTitle = video("BV1", title: "旗舰手机充电速度实测", duration: 300, view: 10_000, like: 500)
        let chargingVideo = video(
            "BV2",
            title: "充电专属花絮",
            duration: 300,
            view: 10_000,
            like: 500,
            isChargingExclusive: true
        )
        let videos = [normalWithChargingTitle, chargingVideo]

        let offConfig = VideoRecommendationFilterConfiguration(
            minimumDurationSeconds: 0,
            minimumViewCount: 0,
            minimumLikeRatioPercent: 0,
            blockedKeywords: [],
            appliesToRelatedVideos: false,
            blocksChargingVideos: false
        )
        XCTAssertEqual(
            VideoRecommendationFilter.filtered(videos, configuration: offConfig, context: .feed).map(\.bvid),
            ["BV1", "BV2"]
        )
        XCTAssertEqual(
            VideoRecommendationFilter.filtered(videos, configuration: offConfig, context: .related).map(\.bvid),
            ["BV1", "BV2"]
        )

        let onConfig = VideoRecommendationFilterConfiguration(
            minimumDurationSeconds: 0,
            minimumViewCount: 0,
            minimumLikeRatioPercent: 0,
            blockedKeywords: [],
            appliesToRelatedVideos: false,
            blocksChargingVideos: true
        )
        XCTAssertEqual(
            VideoRecommendationFilter.filtered(videos, configuration: onConfig, context: .feed).map(\.bvid),
            ["BV1"]
        )
        XCTAssertEqual(
            VideoRecommendationFilter.filtered(videos, configuration: onConfig, context: .related).map(\.bvid),
            ["BV1"]
        )

        // Verify API model decoding for charging-exclusive signals across endpoints
        let recommendJSON = """
        {"bvid":"BV1charge01","title":"专属回放","goto":"av","badge_style":{"text":"充电专属"}}
        """.data(using: .utf8)!
        let decodedRecommend = try JSONDecoder().decode(RecommendFeedItem.self, from: recommendJSON).asVideoItem()
        XCTAssertEqual(decodedRecommend?.isChargingExclusive, true)

        let normalRecommendJSON = """
        {"bvid":"BV1normal01","title":"百瓦快充手机充电测评","goto":"av","rcmd_reason":{"content":"百万播放"}}
        """.data(using: .utf8)!
        let decodedNormalRecommend = try JSONDecoder().decode(RecommendFeedItem.self, from: normalRecommendJSON).asVideoItem()
        XCTAssertEqual(decodedNormalRecommend?.isChargingExclusive, false)

        let searchJSON = """
        {"bvid":"BV1search01","title":"独家内容","is_charge_video":1}
        """.data(using: .utf8)!
        let decodedSearch = try JSONDecoder().decode(SearchVideoItem.self, from: searchJSON).asVideoItem()
        XCTAssertTrue(decodedSearch.isChargingExclusive)

        let relatedJSON = """
        {"bvid":"BV1rel01","title":"充电视频","is_upower_exclusive":true}
        """.data(using: .utf8)!
        let decodedRelated = try JSONDecoder().decode(VideoItem.self, from: relatedJSON)
        XCTAssertTrue(decodedRelated.isChargingExclusive)
    }

    private func video(
        _ bvid: String,
        title: String,
        duration: Int,
        view: Int,
        like: Int,
        isChargingExclusive: Bool = false
    ) -> VideoItem {
        VideoItem(
            bvid: bvid,
            aid: nil,
            title: title,
            pic: nil,
            desc: nil,
            duration: duration,
            pubdate: nil,
            owner: nil,
            stat: VideoStat(view: view, reply: nil, like: like, coin: nil, favorite: nil),
            cid: nil,
            pages: nil,
            dimension: nil,
            isChargingExclusive: isChargingExclusive
        )
    }
}
