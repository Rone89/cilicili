import XCTest
@testable import bili

final class PgcSeasonPlaybackRouteTests: XCTestCase {
    func testEpisodeRouteProvidesImmediatePlayerSeedWithoutInventingPlaybackIDs() throws {
        let route = PgcSeasonRoute(episodeID: 101, seasonID: 100, title: "第1集", cover: "https://example.com/cover.jpg")
        let seed = try XCTUnwrap(route.episodeSeedVideo)
        XCTAssertEqual(seed.bvid, "ep101")
        XCTAssertEqual(seed.pgcEpisodeID, 101)
        XCTAssertEqual(seed.pgcSeasonID, 100)
        XCTAssertEqual(seed.title, route.title)
        XCTAssertEqual(seed.pic, route.cover)
        XCTAssertTrue(seed.isPGCEpisode)
        XCTAssertNil(seed.cid)
        XCTAssertNil(seed.aid)
        XCTAssertNil(seed.pages)
        XCTAssertNil(PgcSeasonRoute(seasonID: 100, title: "番剧", cover: nil).episodeSeedVideo)
        XCTAssertNil(PgcSeasonRoute(episodeID: 0, seasonID: 100, title: "番剧", cover: nil).episodeSeedVideo)
    }

    func testPreferredPlaybackEpisodeUsesCloudResumeEpisode() throws {
        let season = try decodeSeason(
            """
            {
              "season_id": 100,
              "episodes": [
                { "id": 1, "ep_id": 101, "cid": 1001, "title": "1" },
                { "id": 2, "ep_id": 102, "cid": 1002, "title": "2" }
              ],
              "user_status": { "progress": { "last_ep_id": 102 } }
            }
            """
        )

        XCTAssertEqual(season.preferredPlaybackEpisode?.epID, 102)
    }

    func testPreferredPlaybackEpisodeFallsBackToFirstPlayableEpisode() throws {
        let season = try decodeSeason(
            """
            {
              "season_id": 100,
              "episodes": [
                { "id": 1, "ep_id": 101, "title": "不可播放" },
                { "id": 2, "ep_id": 102, "cid": 1002, "title": "可播放" }
              ]
            }
            """
        )

        XCTAssertEqual(season.preferredPlaybackEpisode?.epID, 102)
    }

    func testRequestedEpisodeOverridesCloudResumeAndSupportsSectionEpisodes() throws {
        let season = try decodeSeason(
            """
            {
              "season_id":100,
              "episodes":[{"id":1,"ep_id":101,"cid":1001},{"id":2,"ep_id":102,"cid":1002}],
              "section":[{"episodes":[{"id":3,"ep_id":103,"cid":1003}]}],
              "user_status":{"progress":{"last_ep_id":102}}
            }
            """
        )
        for epID in [101, 103] {
            let route = PgcSeasonRoute(episodeID: epID, seasonID: 100, title: "番剧", cover: nil)
            let video = try XCTUnwrap(route.playbackEpisode(in: season)?.videoItem(in: season))
            XCTAssertEqual(video.pgcEpisodeID, epID)
            XCTAssertEqual(video.pgcSeasonID, 100)
        }
        let seasonRoute = PgcSeasonRoute(seasonID: 100, title: "番剧", cover: nil)
        XCTAssertEqual(seasonRoute.playbackEpisode(in: season)?.epID, 102)
    }

    func testMissingOrUnplayableRequestedEpisodeNeverFallsBack() throws {
        let season = try decodeSeason(
            """
            {"episodes":[{"ep_id":101},{"ep_id":102,"cid":1002}],"user_status":{"progress":{"last_ep_id":102}}}
            """
        )
        for epID in [101, 999] {
            let route = PgcSeasonRoute(episodeID: epID, seasonID: nil, title: "番剧", cover: nil)
            XCTAssertNil(route.playbackEpisode(in: season))
        }
        XCTAssertNotEqual(
            PgcSeasonRoute(episodeID: 101, seasonID: 100, title: "番剧", cover: nil).id,
            PgcSeasonRoute(episodeID: 102, seasonID: 100, title: "番剧", cover: nil).id
        )
    }

    func testExactLookupSkipsUnplayableDuplicatesAndChecksExtraSections() throws {
        let season = try decodeSeason(
            #"{"episodes":[{"ep_id":101},{"ep_id":102,"cid":1002}],"section":[{"episodes":[{"ep_id":101,"cid":1001}]}]}"#
        )
        let route = PgcSeasonRoute(episodeID: 101, seasonID: nil, title: "番剧", cover: nil)
        XCTAssertEqual(route.playbackEpisode(in: season)?.cid, 1001)
    }

    private func decodeSeason(_ json: String) throws -> PgcSeasonInfo {
        try JSONDecoder().decode(PgcSeasonInfo.self, from: Data(json.utf8))
    }
}
