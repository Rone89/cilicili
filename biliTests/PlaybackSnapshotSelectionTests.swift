import UIKit
import XCTest

@testable import bili

@MainActor
final class PlaybackSnapshotSelectionTests: XCTestCase {
    func testUsableVideoFrameSkipsSurfaceCaptureForBothTransitionPaths() throws {
        let engine = PlayerLifecycleEngineSpy(isPlaying: false)
        let player = makePlayer(engine: engine)
        defer { player.stop() }
        let video = image(.white)
        engine.videoFrameImage = video
        engine.surfaceSnapshotImage = image(.red)
        let initialSurfaceReads = engine.surfaceSnapshotImageReadCount
        let initialVideoReads = engine.videoFrameImageReadCount

        let general = try XCTUnwrap(player.makePlaybackTransitionSnapshot())
        let current = try XCTUnwrap(player.makeCurrentVideoFrameTransitionSnapshot())

        XCTAssertTrue(general.image === video)
        XCTAssertTrue(current.image === video)
        XCTAssertTrue(general.isVideoFrame)
        XCTAssertTrue(current.isVideoFrame)
        XCTAssertEqual(engine.videoFrameImageReadCount, initialVideoReads + 2)
        XCTAssertEqual(engine.surfaceSnapshotImageReadCount, initialSurfaceReads,
                       "A usable video frame must not trigger a redundant surface rasterization")
    }

    func testSnapshotViewAlsoSkipsSurfaceCaptureWhenVideoFrameIsUsable() throws {
        let engine = PlayerLifecycleEngineSpy(isPlaying: false)
        let player = makePlayer(engine: engine)
        defer { player.stop() }
        let video = image(.white)
        engine.videoFrameImage = video
        engine.surfaceSnapshotImage = image(.red)
        let initialSurfaceReads = engine.surfaceSnapshotImageReadCount

        let snapshot = try XCTUnwrap(player.makeCurrentVideoFrameSnapshotView() as? UIImageView)

        XCTAssertTrue(snapshot.image === video)
        XCTAssertEqual(engine.surfaceSnapshotImageReadCount, initialSurfaceReads)
    }

    func testMissingAndBlackVideoFramesStillFallBackToCurrentSurface() throws {
        for primary in [nil, image(.black)] as [UIImage?] {
            let engine = PlayerLifecycleEngineSpy(isPlaying: false)
            let player = makePlayer(engine: engine)
            defer { player.stop() }
            let surface = image(.white)
            engine.videoFrameImage = primary
            engine.surfaceSnapshotImage = surface
            let initialSurfaceReads = engine.surfaceSnapshotImageReadCount

            let snapshot = try XCTUnwrap(player.makePlaybackTransitionSnapshot())

            XCTAssertTrue(snapshot.image === surface)
            XCTAssertTrue(snapshot.isVideoFrame)
            XCTAssertEqual(engine.surfaceSnapshotImageReadCount, initialSurfaceReads + 1)
        }
    }

    func testUnusableFreshImagesPreserveCachedFallbackAndItsClassification() throws {
        let engine = PlayerLifecycleEngineSpy(isPlaying: false)
        let player = makePlayer(engine: engine)
        defer { player.stop() }
        let video = image(.white)
        engine.videoFrameImage = video
        _ = try XCTUnwrap(player.makePlaybackTransitionSnapshot())
        engine.videoFrameImage = nil
        engine.surfaceSnapshotImage = image(.black)

        let snapshot = try XCTUnwrap(player.makeCurrentVideoFrameTransitionSnapshot())

        XCTAssertTrue(snapshot.image === video)
        XCTAssertFalse(snapshot.isVideoFrame,
                       "A remembered image must retain the existing fallback classification")
        XCTAssertNil(player.makeCurrentVisibleSurfaceTransitionSnapshot(),
                     "A black current surface must not be replaced by a cached frame in the visible-surface path")
    }

    private func makePlayer(engine: PlayerLifecycleEngineSpy) -> PlayerStateViewModel {
        PlayerStateViewModel(videoURL: nil, audioURL: nil,
                             title: "Snapshot selection", referer: "https://www.bilibili.com", engine: engine)
    }

    private func image(_ color: UIColor) -> UIImage {
        let size = CGSize(width: 16, height: 16)
        return UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
