import Foundation
import XCTest

@testable import bili

final class VideoDetailSubtitleStoreTests: XCTestCase {
    // MARK: - 排序

    func testSortedTracksPutsHumanChineseFirstThenChineseAIThenOthers() {
        let tracks = [
            VideoSubtitleTrack(lan: "en", isAI: true),
            VideoSubtitleTrack(lan: "en"),
            VideoSubtitleTrack(lan: "ai-zh", isAI: true),
            VideoSubtitleTrack(lan: "zh"),
        ]

        let sorted = VideoSubtitlePreference.sortedTracks(tracks)

        XCTAssertEqual(sorted.map(\.lan), ["zh", "ai-zh", "en", "en"])
    }

    func testSortedTracksKeepsOriginalOrderWithinSameGroup() {
        let tracks = [
            VideoSubtitleTrack(lan: "zh-1"),
            VideoSubtitleTrack(lan: "zh-2"),
        ]

        let sorted = VideoSubtitlePreference.sortedTracks(tracks)

        XCTAssertEqual(sorted.map(\.lan), ["zh-1", "zh-2"])
    }

    // MARK: - 偏好选轨

    func testPreferenceWithHumanAndAITracks() {
        let human = VideoSubtitleTrack(lan: "zh", isAI: false)
        let ai = VideoSubtitleTrack(lan: "ai-zh", isAI: true)
        let tracks = [human, ai]

        XCTAssertEqual(VideoSubtitlePreference.off.preferredTrack(in: tracks, isMuted: false), nil)
        XCTAssertEqual(VideoSubtitlePreference.preferHuman.preferredTrack(in: tracks, isMuted: false), human)
        XCTAssertEqual(VideoSubtitlePreference.humanOnly.preferredTrack(in: tracks, isMuted: false), human)
        XCTAssertEqual(VideoSubtitlePreference.autoWhenMuted.preferredTrack(in: tracks, isMuted: false), human)
        XCTAssertEqual(VideoSubtitlePreference.autoWhenMuted.preferredTrack(in: tracks, isMuted: true), human)
    }

    func testPreferenceWithOnlyAITrack() {
        let ai = VideoSubtitleTrack(lan: "ai-zh", isAI: true)
        let tracks = [ai]

        XCTAssertEqual(VideoSubtitlePreference.preferHuman.preferredTrack(in: tracks, isMuted: false), ai)
        XCTAssertEqual(VideoSubtitlePreference.humanOnly.preferredTrack(in: tracks, isMuted: false), nil)
        XCTAssertEqual(VideoSubtitlePreference.autoWhenMuted.preferredTrack(in: tracks, isMuted: false), nil)
        XCTAssertEqual(VideoSubtitlePreference.autoWhenMuted.preferredTrack(in: tracks, isMuted: true), ai)
    }

    func testPreferenceWithNoTracks() {
        XCTAssertEqual(VideoSubtitlePreference.autoWhenMuted.preferredTrack(in: [], isMuted: true), nil)
        XCTAssertEqual(VideoSubtitlePreference.preferHuman.preferredTrack(in: [], isMuted: false), nil)
    }

    // MARK: - Store 状态

    @MainActor
    func testSetTracksSortsAndClearsSelectionWhenEmpty() {
        let store = VideoDetailSubtitleStore()

        store.setTracks([
            VideoSubtitleTrack(lan: "ai-zh", isAI: true),
            VideoSubtitleTrack(lan: "zh"),
        ])
        XCTAssertEqual(store.tracks.map(\.lan), ["zh", "ai-zh"])

        store.setTracks([])
        XCTAssertFalse(store.hasTracks)
        XCTAssertNil(store.selectedLan)
    }

    @MainActor
    func testUpdateCurrentCueFindsCueAtBoundaries() {
        let store = VideoDetailSubtitleStore()
        store.setSelectedLan("zh")
        store.storeCues(
            [
                VideoSubtitleCue(from: 0, to: 2, content: "第一句"),
                VideoSubtitleCue(from: 2, to: 4, content: "第二句"),
                VideoSubtitleCue(from: 4, to: 6, content: "第三句"),
            ],
            for: "zh"
        )

        store.updateCurrentCue(at: 0.5)
        XCTAssertEqual(store.currentCue?.content, "第一句")

        store.updateCurrentCue(at: 2)
        XCTAssertEqual(store.currentCue?.content, "第二句")

        store.updateCurrentCue(at: 3.99)
        XCTAssertEqual(store.currentCue?.content, "第二句")

        store.updateCurrentCue(at: 6)
        XCTAssertNil(store.currentCue)

        store.updateCurrentCue(at: -1)
        XCTAssertNil(store.currentCue)
    }

    @MainActor
    func testSelectingOtherTrackClearsCurrentCueAndCachesPerLan() {
        let store = VideoDetailSubtitleStore()
        store.setTracks([
            VideoSubtitleTrack(lan: "zh"),
            VideoSubtitleTrack(lan: "en"),
        ])

        store.setSelectedLan("zh")
        store.storeCues([VideoSubtitleCue(from: 0, to: 2, content: "中文")], for: "zh")
        store.updateCurrentCue(at: 1)
        XCTAssertEqual(store.currentCue?.content, "中文")

        // 缓存按 lan 独立：切走再切回不需要重新拉取。
        store.setSelectedLan("en")
        XCTAssertNil(store.currentCue)
        store.setSelectedLan("zh")
        XCTAssertNotNil(store.cues(for: "zh"))

        // 未缓存的轨在拉取前不产生 cue。
        store.setSelectedLan("en")
        store.updateCurrentCue(at: 1)
        XCTAssertNil(store.currentCue)
    }
}
