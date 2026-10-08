import XCTest
@testable import bili

@MainActor
final class HomeRecommendationFeedbackTests: XCTestCase {
    func testExperimentDefaultsOffAndPersistsWithoutClearingBlocks() {
        let suite = "HomeFeedbackTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LibraryStore(userDefaults: defaults)
        XCTAssertFalse(store.homeRecommendationFeedbackContextMenuExperimentEnabled)
        store.blockHomeRecommendationUP(mid: 123)
        store.blockHomeRecommendationUP(mid: 123)
        store.blockHomeRecommendationUP(mid: 0)
        XCTAssertEqual(store.blockedHomeRecommendationUPMIDs, [123])
        XCTAssertTrue(store.containsBlockedHomeRecommendationUP(mid: 123))
        store.setHomeRecommendationFeedbackContextMenuExperimentEnabled(true)
        let restored = LibraryStore(userDefaults: defaults)
        XCTAssertTrue(restored.homeRecommendationFeedbackContextMenuExperimentEnabled)
        XCTAssertEqual(restored.blockedHomeRecommendationUPMIDs, [123])
        restored.setHomeRecommendationFeedbackContextMenuExperimentEnabled(false)
        XCTAssertTrue(restored.containsBlockedHomeRecommendationUP(mid: 123))
        restored.unblockHomeRecommendationUP(mid: 123)
        XCTAssertFalse(LibraryStore(userDefaults: defaults).containsBlockedHomeRecommendationUP(mid: 123))
    }

    func testAvailabilityIsOnlyEnabledRecommendation() {
        XCTAssertFalse(HomeRecommendationFeedbackPolicy.isAvailable(experimentEnabled: false, mode: .recommend))
        XCTAssertFalse(HomeRecommendationFeedbackPolicy.isAvailable(experimentEnabled: true, mode: .popular))
        XCTAssertTrue(HomeRecommendationFeedbackPolicy.isAvailable(experimentEnabled: true, mode: .recommend))
    }

    func testMIDFilterPreservesOrderUnknownOwnersAndExactLegacyOff() throws {
        let videos = try [123, 456, 123, 789].enumerated().map { try HomeFeedbackTestData.video(id: $0.offset + 1, mid: $0.element) }
        XCTAssertEqual(HomeRecommendationFeedbackPolicy.filtered(videos, blockedMIDs: [123], enabled: true).map(\.owner?.mid), [456, 789])
        XCTAssertEqual(HomeRecommendationFeedbackPolicy.filtered(videos, blockedMIDs: [123], enabled: false), videos)
        let unknown = try JSONDecoder.bili.decode(VideoItem.self, from: Data(#"{"bvid":"unknown","title":"unknown"}"#.utf8))
        XCTAssertEqual(HomeRecommendationFeedbackPolicy.filtered([unknown], blockedMIDs: [123], enabled: true), [unknown])
    }

    func testAPPReasonsParseWithoutInventingWebFeedback() throws {
        let video = try HomeFeedbackTestData.video()
        let metadata = try XCTUnwrap(video.recommendationFeedback)
        XCTAssertEqual(metadata.goto, "av")
        XCTAssertEqual(metadata.targetID, 1001)
        let dislike = metadata.reasons(for: .dislike)
        XCTAssertEqual(dislike.map(\.id), [7])
        XCTAssertEqual(dislike.first?.name, "不想看此类内容")
        XCTAssertEqual(dislike.first?.toast, "将减少此类推荐")
        XCTAssertEqual(metadata.reasons(for: .feedback).map(\.id), [8])
        let web = try JSONDecoder.bili.decode(RecommendFeedItem.self, from: Data(#"{"id":1001,"bvid":"BVweb","title":"Web","owner":{"mid":123,"name":"UP"}}"#.utf8))
        XCTAssertNil(web.asVideoItem()?.recommendationFeedback)
    }

    func testMetadataSurvivesHydrationSnapshotAndCellCacheUpdates() throws {
        let video = try HomeFeedbackTestData.video()
        let detail = try JSONDecoder.bili.decode(VideoItem.self, from: Data(#"{"bvid":"BV1","title":"详情"}"#.utf8))
        XCTAssertEqual(video.mergingFilledValues(from: detail).recommendationFeedback, video.recommendationFeedback)
        let cached = HomeFeedCachedVideo(video: video)
        let restored = try JSONDecoder.bili.decode(HomeFeedCachedVideo.self, from: JSONEncoder().encode(cached))
        XCTAssertEqual(restored.videoItem.recommendationFeedback, video.recommendationFeedback)
        let legacy = try JSONDecoder.bili.decode(HomeFeedCachedVideo.self, from: Data(#"{"bvid":"old","title":"旧缓存"}"#.utf8))
        XCTAssertNil(legacy.recommendationFeedback)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(cached)) as? [String: Any])
        object.removeValue(forKey: "recommendationFeedback")
        let without = try JSONDecoder.bili.decode(HomeFeedCachedVideo.self, from: JSONSerialization.data(withJSONObject: object)).videoItem
        var cells = HomeFeedCellStore()
        _ = cells.update(with: [without])
        XCTAssertEqual(cells.update(with: [video]).first?.video.recommendationFeedback, video.recommendationFeedback)
    }
}

nonisolated enum HomeFeedbackTestData {
    static func video(id: Int = 1, mid: Int = 123) throws -> VideoItem {
        let json = """
        {"id":9999,"param":"\(1000 + id)","bvid":"BV\(id)","card_goto":"av","goto":"av","title":"推荐\(id)","owner":{"mid":\(mid),"name":"UP\(mid)"},
         "three_point_v2":[
           {"type":"dislike","reasons":[{"id":"7","name":"不想看此类内容","toast":"将减少此类推荐"},{"id":7,"name":"重复"},{"id":9},{"name":"无 ID"}]},
           {"type":"feedback","reasons":[{"id":8,"name":"看过了","toast":"已反馈"}]},
           {"type":"watch_later","title":"稍后再看"}]}
        """
        return try XCTUnwrap(JSONDecoder.bili.decode(RecommendFeedItem.self, from: Data(json.utf8)).asVideoItem())
    }
}
