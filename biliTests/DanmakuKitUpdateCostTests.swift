import UIKit
import XCTest
@testable import bili

@MainActor
final class DanmakuKitUpdateCostTests: XCTestCase {
    func testRepeatedPlaybackAndLayoutUpdatesReusePreparedItemsAndTracks() throws {
        let view = DanmakuKitOverlayView(frame: CGRect(x: 0, y: 0, width: 390, height: 300))
        let items = [item("later", time: 3), item("visible", time: 0)]
        apply(view, items: items, revision: 0)
        view.layoutIfNeeded()
        let renderer = try XCTUnwrap(view.subviews.first)
        let cells = renderer.subviews.map(ObjectIdentifier.init)
        XCTAssertFalse(cells.isEmpty, "Exercise the real renderer with visible fixed danmaku")
        let configurationCount = view.debugRendererConfigurationCount

        for _ in 0..<120 {
            apply(view, items: items, revision: 0)
            view.setNeedsLayout()
            view.layoutIfNeeded()
            view.synchronizePlaybackTime(1)
        }
        XCTAssertEqual(view.debugItemPreparationCount, 1)
        XCTAssertEqual(view.debugRendererConfigurationCount, configurationCount)
        XCTAssertEqual(view.debugPreparedItemIDs, ["visible", "later"])
        XCTAssertEqual(renderer.subviews.map(ObjectIdentifier.init), cells,
                       "Updates must preserve the actual on-screen cells")
        view.stop()
    }

    func testNewRevisionSettingsAndViewportStillApply() {
        let view = DanmakuKitOverlayView(frame: CGRect(x: 0, y: 0, width: 390, height: 300))
        let items = [item("b", time: 1), item("a", time: 1), item("invalid", time: .nan)]
        apply(view, items: items, revision: 0)
        XCTAssertEqual(view.debugPreparedItemIDs, ["a", "b"])
        apply(view, items: [item("new", time: 0)], revision: 1)
        XCTAssertEqual(view.debugPreparedItemIDs, ["new"])
        XCTAssertEqual(view.debugItemPreparationCount, 2)
        var settings = DanmakuSettings.default
        settings.danmakuKit.enablesTop = false
        let before = view.debugRendererConfigurationCount
        apply(view, items: [item("new", time: 0)], revision: 1, settings: settings)
        XCTAssertEqual(view.debugRendererConfigurationCount, before + 1)
        view.frame.size.height += 100
        view.setNeedsLayout()
        view.layoutIfNeeded()
        XCTAssertEqual(view.debugRendererConfigurationCount, before + 2)
        XCTAssertEqual(view.debugItemPreparationCount, 2)
        view.stop()
    }

    private func apply(
        _ view: DanmakuKitOverlayView, items: [DanmakuItem], revision: Int,
        settings: DanmakuSettings = .default
    ) {
        view.apply(items: items, itemsRevision: revision, currentTime: 1,
                   isPlaying: false, playbackRate: 1, isEnabled: true,
                   hasPresentedPlayback: true, isLoadShedding: false,
                   settings: settings, topInset: 8, bottomInset: 54)
    }

    private func item(_ id: String, time: TimeInterval) -> DanmakuItem {
        DanmakuItem(id: id, time: time, mode: 5, fontSize: 25, color: 0xFFFFFF, text: id)
    }
}
