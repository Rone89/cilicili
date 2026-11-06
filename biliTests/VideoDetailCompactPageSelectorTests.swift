import Foundation
import XCTest

@testable import bili

final class VideoDetailCompactPageSelectorTests: XCTestCase {
    @MainActor
    func testCompactPageSelectorDefaultsToOffAndPersists() {
        let defaults = makeUserDefaults()
        XCTAssertFalse(LibraryStore(userDefaults: defaults).videoDetailCompactPageSelectorExperimentEnabled)

        let store = LibraryStore(userDefaults: defaults)
        store.setVideoDetailCompactPageSelectorExperimentEnabled(true)
        XCTAssertTrue(LibraryStore(userDefaults: defaults).videoDetailCompactPageSelectorExperimentEnabled)

        store.setVideoDetailCompactPageSelectorExperimentEnabled(false)
        XCTAssertFalse(LibraryStore(userDefaults: defaults).videoDetailCompactPageSelectorExperimentEnabled)
    }

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

    private func makeUserDefaults() -> UserDefaults {
        let name = "VideoDetailCompactPageSelectorTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
