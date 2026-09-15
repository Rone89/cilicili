import XCTest
@testable import bili

final class AccountWatchLaterEntryTests: XCTestCase {
    func testWatchLaterEntryUsesAddedTimestampAndKeepsResumeProgress() throws {
        let payload = try decodePayload(
            """
            {
              "count": 1,
              "list": [{
                "aid": 112233,
                "bvid": "BV1ToView0001",
                "title": "稍后再看的视频",
                "pic": "http://i0.hdslb.com/cover.jpg",
                "duration": 600,
                "cid": 445566,
                "progress": 120,
                "add_at": 1720000000,
                "ctime": 1600000000,
                "owner": { "mid": 99, "name": "测试 UP", "face": "http://i0.hdslb.com/face.jpg" },
                "stat": { "view": 4321, "reply": 12, "like": 34, "coin": 5, "favorite": 6 }
              }]
            }
            """
        )

        let entry = try XCTUnwrap(payload.accountVideoEntries.first)

        XCTAssertEqual(entry.bvid, "BV1ToView0001")
        XCTAssertEqual(entry.aid, 112233)
        XCTAssertEqual(entry.title, "稍后再看的视频")
        XCTAssertEqual(entry.owner?.name, "测试 UP")
        XCTAssertEqual(entry.stat?.view, 4321)
        XCTAssertEqual(entry.savedAt, Date(timeIntervalSince1970: 1_720_000_000))
        XCTAssertEqual(entry.resumeTime, 120)
        XCTAssertEqual(entry.videoItem.historyCID, 445566)
        XCTAssertFalse(entry.videoItem.isPGCEpisode)
    }

    func testFinishedWatchLaterEntryDoesNotOfferResume() throws {
        let payload = try decodePayload(
            """
            {
              "count": 1,
              "list": [{
                "aid": 445566,
                "bvid": "BV1ToView0002",
                "title": "已看完的视频",
                "duration": 300,
                "progress": -1,
                "add_at": 1720000001
              }]
            }
            """
        )

        let entry = try XCTUnwrap(payload.accountVideoEntries.first)

        XCTAssertNil(entry.resumeTime)
        XCTAssertEqual(entry.playbackProgress, 1)
        XCTAssertEqual(entry.savedAt, Date(timeIntervalSince1970: 1_720_000_001))
    }

    func testHistoryEntryStillPrefersViewTimestampOverAddedTimestamp() throws {
        let payload = try decodePayload(
            """
            {
              "list": [{
                "bvid": "BV1History001",
                "title": "观看记录",
                "duration": 300,
                "view_at": 1720000500,
                "add_at": 1720000000
              }]
            }
            """
        )

        let entry = try XCTUnwrap(payload.accountVideoEntries.first)

        XCTAssertEqual(entry.savedAt, Date(timeIntervalSince1970: 1_720_000_500))
    }

    private func decodePayload(_ json: String) throws -> DynamicJSONValue {
        try JSONDecoder().decode(DynamicJSONValue.self, from: Data(json.utf8))
    }
}
