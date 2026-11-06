import Foundation
import XCTest

@testable import bili

final class VideoDetailCompactPageSelectorTests: XCTestCase {
    @MainActor
    func testCompactPageSelectorSnapshotExposesCurrentSelectionAndCount() {
        let coverVideo = VideoItem(
            bvid: "BVTest", aid: 1, title: "测试", pic: "https://example.com/pic.jpg",
            desc: nil, duration: 120, pubdate: nil, owner: nil, stat: nil, cid: 1001,
            pages: nil, dimension: nil
        )
        let store = VideoDetailPageSelectorRenderStore()
        store.update(VideoDetailPageSelectorRenderSnapshot(
            playback: VideoDetailPlaybackRenderSnapshot(
                pages: [
                    VideoPage(cid: 1001, page: 1, part: "测试分 P", duration: 120, dimension: nil),
                    VideoPage(cid: 1002, page: 2, part: "第二分 P", duration: 90, dimension: nil),
                    VideoPage(cid: 1003, page: 3, part: "第三分 P", duration: 60, dimension: nil),
                ],
                coverDisplay: VideoCardDisplayModel(video: coverVideo),
                selectedCID: 1002,
                isDetailLoaded: true
            )
        ))

        XCTAssertTrue(store.shouldShowPageSelector)
        XCTAssertEqual(store.pages.count, 3)
        XCTAssertEqual(store.selectedCID, 1002)
        XCTAssertEqual(store.coverDisplay?.id, coverVideo.id)
        XCTAssertNotNil(store.coverDisplay?.sourceCoverURL)
        let selectedPart = store.pages.first { $0.cid == store.selectedCID }
        XCTAssertEqual(selectedPart?.part, "第二分 P")
    }

    @MainActor
    func testPageItemMapsToCompactSelectionItem() {
        let page = VideoPage(cid: 1002, page: 2, part: " 第二分 P ", duration: 90, dimension: nil)
        let item = VideoDetailCompactSelectionItem(
            page: page,
            isSelected: true,
            fallbackCoverURL: "https://example.com/pic.jpg"
        )

        XCTAssertEqual(item.id, 1002)
        XCTAssertEqual(item.displayTitle, "第二分 P")
        XCTAssertEqual(item.numberLabel, "P2")
        XCTAssertNotNil(item.durationText)
        XCTAssertEqual(item.coverURLString, "https://example.com/pic.jpg")
        XCTAssertTrue(item.isSelected)
        XCTAssertTrue(item.isSelectable)
    }

    @MainActor
    func testPageWithoutPartFallsBackToNumberTitle() {
        let page = VideoPage(cid: 1001, page: 1, part: "   ", duration: nil, dimension: nil)
        let item = VideoDetailCompactSelectionItem(
            page: page,
            isSelected: false,
            fallbackCoverURL: nil
        )

        XCTAssertEqual(item.displayTitle, "P1")
        XCTAssertNil(item.durationText)
        XCTAssertNil(item.coverURLString)
    }

    @MainActor
    func testEpisodeItemMapsToCompactSelectionItem() throws {
        let season = try decodeSeason()
        let episodes = season.selectableEpisodes
        XCTAssertEqual(episodes.count, 3)

        let first = VideoDetailCompactSelectionItem(
            episode: episodes[0],
            season: season,
            isSelected: true
        )
        XCTAssertEqual(first.displayTitle, "第1话 分集标题1")
        XCTAssertNil(first.numberLabel)
        XCTAssertEqual(first.coverURLString, "https://ui-test.invalid/ep1.jpg")
        XCTAssertTrue(first.isSelectable)
        XCTAssertEqual(first.selectVideo?.pgcEpisodeID, 3001)
        XCTAssertTrue(first.isSelected)

        // badge 为空字符串时不输出角标。
        XCTAssertNotNil(episodes[2].badge)
    }

    @MainActor
    func testEpisodeWithoutCoverOrCidIsNotSelectable() throws {
        let json = #"""
        {"season_id":30,"cover":"https://ui-test.invalid/season.jpg","episodes":[
          {"id":4001,"cid":0,"title":"无CID","cover":"https://ui-test.invalid/a.jpg"},
          {"id":4002,"cid":4002,"title":"有CID无封面","cover":""}
        ]}
        """#
        let season = try JSONDecoder.bili.decode(PgcSeasonInfo.self, from: Data(json.utf8))
        let episodes = season.allPlayableEpisodes

        // 无 CID 的集不会出现在可播放列表；有 CID 无封面则置灰不可选。
        XCTAssertEqual(episodes.map(\.id), [4002])
        let item = VideoDetailCompactSelectionItem(episode: episodes[0], season: season, isSelected: false)
        // 该集会回落到季封面，因此仍可选。
        XCTAssertEqual(item.coverURLString, "https://ui-test.invalid/season.jpg")
        XCTAssertTrue(item.isSelectable)
    }

    @MainActor
    func testEpisodeWithoutAnyCoverIsGreyedOut() throws {
        let seasonData = #"{"season_id":30,"episodes":[{"id":5001,"cid":5001,"title":"裸集"}]}"#
        let season = try JSONDecoder.bili.decode(PgcSeasonInfo.self, from: Data(seasonData.utf8))
        let episode = try XCTUnwrap(season.selectableEpisodes.first)

        let item = VideoDetailCompactSelectionItem(episode: episode, season: season, isSelected: false)
        XCTAssertNil(item.coverURLString)
        XCTAssertFalse(item.isSelectable)
        XCTAssertNil(item.selectVideo)
    }

    // MARK: - UGC 合集

    private func decodeUgcSeason() throws -> UgcSeason {
        let json = #"""
        {"id":900,"title":"测试合集","cover":"https://ui-test.invalid/season.jpg","sections":[
          {"id":1,"title":"正片","episodes":[
            {"id":901,"aid":901,"bvid":"BVSeason1","cid":2001,"title":"合集视频 1",
             "cover":"https://ui-test.invalid/season-ep1.jpg","duration":120},
            {"id":902,"aid":902,"bvid":"BVSeason2","cid":2002,"title":"合集视频 2",
             "cover":"https://ui-test.invalid/season-ep2.jpg","duration":90}
          ]},
          {"id":2,"title":"花絮","episodes":[
            {"id":903,"arc":{"aid":903,"bvid":"BVSeason3","cid":2003,"title":"合集视频 3",
             "pic":"https://ui-test.invalid/season-ep3.jpg","duration":60000}}
          ]}
        ]}
        """#
        return try JSONDecoder.bili.decode(UgcSeason.self, from: Data(json.utf8))
    }

    @MainActor
    func testUgcSeasonDecodesAndFlattensSectionEpisodes() throws {
        let season = try decodeUgcSeason()
        XCTAssertEqual(season.episodes.count, 3)
        XCTAssertEqual(season.displayTitle, "测试合集")
        XCTAssertEqual(season.normalizedCover, "https://ui-test.invalid/season.jpg")
        // 第三集只有 arc 档案对象，标题/封面/时长应回落；毫秒时长归一到秒。
        let third = season.episodes[2]
        XCTAssertEqual(third.displayTitle, "合集视频 3")
        XCTAssertEqual(third.resolvedCover, "https://ui-test.invalid/season-ep3.jpg")
        XCTAssertEqual(third.durationSeconds, 60)
        XCTAssertTrue(third.isPlayable)
    }

    @MainActor
    func testUgcSeasonEpisodeItemMapsToCompactSelectionItem() throws {
        let season = try decodeUgcSeason()
        let episode = season.episodes[1]

        let item = VideoDetailCompactSelectionItem(
            ugcSeasonEpisode: episode,
            season: season,
            isSelected: true
        )
        XCTAssertEqual(item.id, 902)
        XCTAssertEqual(item.displayTitle, "合集视频 2")
        XCTAssertNil(item.numberLabel)
        XCTAssertNotNil(item.durationText)
        XCTAssertEqual(item.coverURLString, "https://ui-test.invalid/season-ep2.jpg")
        XCTAssertTrue(item.isSelected)
        XCTAssertTrue(item.isSelectable)
        let video = try XCTUnwrap(item.selectVideo)
        XCTAssertEqual(video.bvid, "BVSeason2")
        XCTAssertEqual(video.cid, 2002)
        // 原地切换时合集数据要带到新条目上，区块才能继续显示。
        XCTAssertEqual(video.ugcSeason?.displayTitle, "测试合集")
    }

    @MainActor
    func testUgcSeasonEpisodeWithoutBvidIsNotSelectable() throws {
        let json = #"{"id":910,"sections":[{"episodes":[{"id":911,"cid":2011,"title":"缺bvid"}]}]}"#
        let season = try JSONDecoder.bili.decode(UgcSeason.self, from: Data(json.utf8))
        let episode = try XCTUnwrap(season.episodes.first)

        let item = VideoDetailCompactSelectionItem(
            ugcSeasonEpisode: episode,
            season: season,
            isSelected: false
        )
        XCTAssertFalse(item.isSelectable)
        XCTAssertNil(item.selectVideo)
    }

    @MainActor
    func testVideoItemMergesUgcSeasonFromFullDetail() {
        let base = VideoItem(
            bvid: "BVSeason2", aid: 902, title: "合集视频 2", pic: nil,
            desc: nil, duration: 90, pubdate: nil, owner: nil, stat: nil,
            cid: 2002, pages: nil, dimension: nil
        )
        let fullDetail = VideoItem(
            bvid: "BVSeason2", aid: 902, title: "合集视频 2", pic: "https://example.com/pic.jpg",
            desc: "完整简介", duration: 90, pubdate: nil, owner: nil, stat: nil,
            cid: 2002, pages: nil, dimension: nil,
            ugcSeason: UgcSeason(id: 900, title: "测试合集", cover: nil, sections: [])
        )

        let merged = base.mergingFilledValues(from: fullDetail)
        XCTAssertEqual(merged.ugcSeason?.title, "测试合集")
        XCTAssertEqual(merged.desc, "完整简介")
    }

    @MainActor
    func testUgcSeasonEpisodeMatchesDetailByBvid() throws {
        let season = try decodeUgcSeason()
        let current = VideoItem(
            bvid: "BVSeason2", aid: 902, title: "合集视频 2", pic: nil,
            desc: nil, duration: 90, pubdate: nil, owner: nil, stat: nil,
            cid: 2002, pages: nil, dimension: nil
        )
        XCTAssertTrue(season.episodes[1].matches(detail: current))
        XCTAssertFalse(season.episodes[0].matches(detail: current))
    }

    private func decodeSeason() throws -> PgcSeasonInfo {
        let json = #"""
        {"season_id":30,"media_id":300,"title":"测试番剧","season_title":"测试番剧",
         "cover":"https://ui-test.invalid/season.jpg","episodes":[
          {"id":3001,"aid":3001,"cid":3001,"ep_id":3001,"title":"第1话","long_title":"分集标题1",
           "cover":"https://ui-test.invalid/ep1.jpg","badge":"","duration":120},
          {"id":3002,"aid":3002,"cid":3002,"ep_id":3002,"title":"第2话","long_title":"分集标题2",
           "cover":"https://ui-test.invalid/ep2.jpg","badge":"","duration":120},
          {"id":3003,"aid":3003,"cid":3003,"ep_id":3003,"title":"第3话","long_title":"分集标题3",
           "cover":"https://ui-test.invalid/ep3.jpg","badge":"预告","duration":120}
        ]}
        """#
        return try JSONDecoder.bili.decode(PgcSeasonInfo.self, from: Data(json.utf8))
    }
}
