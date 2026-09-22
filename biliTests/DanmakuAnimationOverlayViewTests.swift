import XCTest
import UIKit
@testable import bili

final class DanmakuAnimationOverlayViewTests: XCTestCase {
    @MainActor
    func testLayoutTransitionPreservesActiveEntryAndDerivesFrameFromPlaybackTime() throws {
        let view = DanmakuAnimationOverlayView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        view.layoutIfNeeded()
        XCTAssertEqual(view.contentMode, .redraw)
        view.apply(
            items: [DanmakuItem(id: "rotation", time: 1, mode: 5, fontSize: 25, color: 0x00FF_FFFF, text: "rotation")],
            itemsRevision: 1,
            currentTime: 2,
            isPlaying: true,
            playbackRate: 1,
            isEnabled: true,
            hasPresentedPlayback: true,
            isLoadShedding: false,
            settings: .default,
            topInset: 8,
            bottomInset: 54
        )

        XCTAssertTrue(view.activeEntryIDs.contains("rotation"))
        let portraitCenter = try XCTUnwrap(view.activeEntryPosition(for: "rotation"))
        let portraitFontSize = try XCTUnwrap(view.activeEntryFontSize(for: "rotation"))

        view.setLayoutTransitioning(true)
        view.frame = CGRect(x: 0, y: 0, width: 640, height: 360)
        view.layoutIfNeeded()

        // Fixed entries remain centered in the new surface while retaining
        // their cached font metrics.
        let landscapeCenter = try XCTUnwrap(view.activeEntryPosition(for: "rotation"))
        XCTAssertNotEqual(landscapeCenter, portraitCenter)

        view.setLayoutTransitioning(false)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.20))

        let reconciledCenter = try XCTUnwrap(view.activeEntryPosition(for: "rotation"))
        XCTAssertEqual(reconciledCenter.x, 320, accuracy: 0.5)
        let reconciledFontSize = try XCTUnwrap(view.activeEntryFontSize(for: "rotation"))
        XCTAssertEqual(reconciledFontSize, portraitFontSize, accuracy: 0.01)
        XCTAssertGreaterThan(reconciledCenter.y, 0)
        XCTAssertLessThan(reconciledCenter.y, view.bounds.height)
    }

    @MainActor
    func testScrollingEntryKeepsTimeDrivenPositionAcrossRotation() throws {
        let view = DanmakuAnimationOverlayView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        view.layoutIfNeeded()
        view.apply(
            items: [DanmakuItem(id: "scrolling-rotation", time: 1, mode: 1, fontSize: 25, color: 0x00FF_FFFF, text: "scrolling")],
            itemsRevision: 1,
            currentTime: 2,
            isPlaying: true,
            playbackRate: 1,
            isEnabled: true,
            hasPresentedPlayback: true,
            isLoadShedding: false,
            settings: .default,
            topInset: 8,
            bottomInset: 54
        )

        XCTAssertTrue(view.activeEntryIDs.contains("scrolling-rotation"))
        let portraitFontSize = try XCTUnwrap(view.activeEntryFontSize(for: "scrolling-rotation"))
        let portraitCenter = try XCTUnwrap(view.activeEntryPosition(for: "scrolling-rotation"))
        let portraitProgress = try XCTUnwrap(
            view.activeEntryProgress(for: "scrolling-rotation", at: 2)
        )

        view.setLayoutTransitioning(true)
        view.frame = CGRect(x: 0, y: 0, width: 640, height: 360)
        view.layoutIfNeeded()
        let transitionCenter = try XCTUnwrap(view.activeEntryPosition(for: "scrolling-rotation", at: 2))
        let transitionProgress = try XCTUnwrap(
            view.activeEntryProgress(for: "scrolling-rotation", at: 2)
        )
        // PiliPlus keeps an entry on the same media-time trajectory while its
        // parent viewport rotates. A bounds change must not restart it from a
        // newly computed landscape start point.
        XCTAssertEqual(transitionCenter.x, portraitCenter.x, accuracy: 0.5)
        XCTAssertEqual(transitionProgress, portraitProgress, accuracy: 0.001)
        view.setLayoutTransitioning(false)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.20))

        XCTAssertTrue(view.activeEntryIDs.contains("scrolling-rotation"))
        let landscapeFontSize = try XCTUnwrap(view.activeEntryFontSize(for: "scrolling-rotation"))
        XCTAssertEqual(landscapeFontSize, portraitFontSize, accuracy: 0.01)
        let center = try XCTUnwrap(view.activeEntryPosition(for: "scrolling-rotation", at: 2))
        XCTAssertEqual(center.x, portraitCenter.x, accuracy: 0.5)
    }

    @MainActor
    func testScrollingEntryMovesRightToLeftWithMediaTime() throws {
        let view = DanmakuAnimationOverlayView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        view.layoutIfNeeded()
        view.apply(
            items: [DanmakuItem(id: "direction", time: 1, mode: 1, fontSize: 25, color: 0x00FF_FFFF, text: "direction")],
            itemsRevision: 1,
            currentTime: 1.5,
            isPlaying: false,
            playbackRate: 1,
            isEnabled: true,
            hasPresentedPlayback: true,
            isLoadShedding: false,
            settings: .default,
            topInset: 8,
            bottomInset: 54
        )

        let earlier = try XCTUnwrap(view.activeEntryPosition(for: "direction", at: 1.5))
        let later = try XCTUnwrap(view.activeEntryPosition(for: "direction", at: 2.5))
        XCTAssertLessThan(later.x, earlier.x)
    }

    @MainActor
    func testScrollingLayerKeepsPresentationPositionDuringIntermediateRotationLayout() throws {
        let view = DanmakuAnimationOverlayView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        view.layoutIfNeeded()
        view.apply(
            items: [DanmakuItem(id: "paused-rotation", time: 1, mode: 1, fontSize: 25, color: 0x00FF_FFFF, text: "paused")],
            itemsRevision: 1,
            currentTime: 2,
            isPlaying: false,
            playbackRate: 1,
            isEnabled: true,
            hasPresentedPlayback: true,
            isLoadShedding: false,
            settings: .default,
            topInset: 8,
            bottomInset: 54
        )

        let portraitLayerPosition = try XCTUnwrap(view.activeEntryLayerPosition(for: "paused-rotation"))
        view.setLayoutTransitioning(true)
        view.frame = CGRect(x: 0, y: 0, width: 640, height: 360)
        view.layoutIfNeeded()

        let intermediateLayerPosition = try XCTUnwrap(view.activeEntryLayerPosition(for: "paused-rotation"))
        XCTAssertEqual(intermediateLayerPosition.x, portraitLayerPosition.x, accuracy: 0.5)
        XCTAssertEqual(intermediateLayerPosition.y, portraitLayerPosition.y, accuracy: 0.5)
    }
}
