import XCTest
@testable import bili

@MainActor
final class MetalDanmakuStageTransitionTests: XCTestCase {
    func testAspectFitMapsLogicalStageIntoTargetWithoutStretching() {
        let transform = MetalDanmakuStageTransform.aspectFit(
            from: CGSize(width: 900, height: 500),
            into: CGSize(width: 500, height: 900)
        )

        XCTAssertEqual(transform.scale, 5.0 / 9.0, accuracy: 0.001)
        XCTAssertEqual(transform.translation.x, 0, accuracy: 0.001)
        XCTAssertEqual(transform.translation.y, (900 - 500.0 * 5.0 / 9.0) / 2, accuracy: 0.001)
        let mapped = transform.map(CGRect(x: 0, y: 0, width: 900, height: 500))
        XCTAssertEqual(mapped.origin.x, 0, accuracy: 0.001)
        XCTAssertEqual(mapped.origin.y, transform.translation.y, accuracy: 0.001)
        XCTAssertEqual(mapped.width, 500, accuracy: 0.001)
        XCTAssertEqual(mapped.height, 500.0 * 5.0 / 9.0, accuracy: 0.001)
    }

    func testVideoViewportUsesActualAspectFitRectAndPreservesOrigin() {
        let bounds = CGRect(x: 12, y: 24, width: 500, height: 900)
        let viewport = MetalDanmakuVideoViewport.aspectFit(in: bounds, aspectRatio: 16.0 / 9.0)

        XCTAssertEqual(viewport.minX, 12, accuracy: 0.001)
        XCTAssertEqual(viewport.minY, 24 + (900 - 500 / (16.0 / 9.0)) / 2, accuracy: 0.001)
        XCTAssertEqual(viewport.width, 500, accuracy: 0.001)
        XCTAssertEqual(viewport.height, 500 / (16.0 / 9.0), accuracy: 0.001)
    }

    func testUnknownOrInvalidVideoAspectFallsBackToBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 400)
        XCTAssertEqual(MetalDanmakuVideoViewport.aspectFit(in: bounds, aspectRatio: nil), bounds)
        XCTAssertEqual(MetalDanmakuVideoViewport.aspectFit(in: bounds, aspectRatio: .nan), bounds)
        XCTAssertEqual(MetalDanmakuVideoViewport.aspectFit(in: bounds, aspectRatio: 0), bounds)
    }

    func testFontNormalizationConvergesInBothOrientationDirectionsWithoutResettingMotion() throws {
        let settings = DanmakuSettings(hidesInPortrait: false,
            danmakuKit: DanmakuKitRenderSettings(displayArea: .full, allowsDanmakuOverlap: true))
        let item = DanmakuItem(id: "font-stage", time: 0, mode: 1, fontSize: 25,
                               color: 0xFFFFFF, text: "同字号弹幕")
        let cases: [(source: CGSize, target: CGSize, sourceFont: CGFloat, targetFont: CGFloat)] = [
            (CGSize(width: 500, height: 280), CGSize(width: 900, height: 504), 17.5, 21.5),
            (CGSize(width: 900, height: 504), CGSize(width: 500, height: 280), 21.5, 17.5)
        ]

        for testCase in cases {
            let timeline = MetalDanmakuTimeline()
            timeline.viewport = testCase.source
            timeline.settings = settings
            let oldLayout = DanmakuGlyphLayout(
                size: CGSize(width: 240, height: testCase.sourceFont),
                fontPointSize: testCase.sourceFont,
                glyphs: []
            )
            timeline.replaceItems([item], at: 1) { _ in oldLayout.size }
            let before = try XCTUnwrap(timeline.active.first)
            let transform = MetalDanmakuStageTransform.aspectFit(from: testCase.source,
                                                                  into: testCase.target)
            timeline.rebaseActive(using: transform, at: 1)
            let rebased = try XCTUnwrap(timeline.active.first)
            timeline.viewport = testCase.target

            let targetLayout = DanmakuGlyphLayout(
                size: CGSize(width: 240 * testCase.targetFont / testCase.sourceFont,
                             height: testCase.targetFont),
                fontPointSize: testCase.targetFont,
                glyphs: []
            )
            timeline.normalizeActiveFonts(at: 1, hostTime: 10, duration: 0.14,
                layouts: [item.id: (previous: oldLayout, target: targetLayout)])

            let settling = try XCTUnwrap(timeline.active.first)
            XCTAssertEqual(settling.item.id, before.item.id)
            XCTAssertEqual(settling.lane, before.lane)
            XCTAssertEqual(settling.item.time, before.item.time)
            XCTAssertEqual(settling.endTime, before.endTime)
            XCTAssertEqual(settling.velocity, before.velocity * transform.scale, accuracy: 0.001)
            XCTAssertEqual(settling.glyphScale(at: 10), transform.scale * testCase.sourceFont / testCase.targetFont,
                           accuracy: 0.001)
            XCTAssertEqual(settling.glyphScale(at: 10.14), 1, accuracy: 0.001)
            let rebasedFrame = rebased.frame(at: 1)
            let settlingFrame = settling.frame(at: 1)
            XCTAssertEqual(settlingFrame.minX, rebasedFrame.minX, accuracy: 0.01)
            XCTAssertEqual(settlingFrame.minY, rebasedFrame.minY, accuracy: 0.01)
            XCTAssertEqual(settlingFrame.width, rebasedFrame.width, accuracy: 0.01)
            XCTAssertEqual(settlingFrame.height, rebasedFrame.height, accuracy: 0.01)

            XCTAssertTrue(timeline.completeFontScaleSettles(at: 10.14) { _ in targetLayout })
            let settled = try XCTUnwrap(timeline.active.first)
            XCTAssertEqual(settled.glyphScale, 1, accuracy: 0.001)
            XCTAssertEqual(settled.size, targetLayout.size)
            XCTAssertFalse(timeline.hasActiveFontScaleSettle(at: 10.14))
        }
    }

    func testInterruptedFontSettleMaterializesWithoutMovingFixedAnchors() throws {
        let settings = DanmakuSettings(hidesInPortrait: false,
            danmakuKit: DanmakuKitRenderSettings(displayArea: .full, allowsDanmakuOverlap: true))

        for mode in [4, 5] {
            let item = DanmakuItem(id: "fixed-\(mode)", time: 0, mode: mode, fontSize: 25,
                                   color: 0xFFFFFF, text: "锚点弹幕")
            let previous = DanmakuGlyphLayout(size: CGSize(width: 180, height: 22),
                                              fontPointSize: 21.5, glyphs: [])
            let target = DanmakuGlyphLayout(size: CGSize(width: 145, height: 18),
                                            fontPointSize: 17.5, glyphs: [])
            let timeline = MetalDanmakuTimeline()
            timeline.viewport = CGSize(width: 500, height: 280)
            timeline.settings = settings
            timeline.replaceItems([item], at: 1) { _ in previous.size }
            timeline.normalizeActiveFonts(at: 1, hostTime: 10, duration: 0.14,
                layouts: [item.id: (previous: previous, target: target)])

            let before = try XCTUnwrap(timeline.active.first)
            let scale = before.glyphScale(at: 10.07)
            let anchorX: CGFloat = 0.5
            let anchorY: CGFloat = item.isBottomAnchored ? 1 : 0
            let visibleLeftBefore = before.startX + (1 - scale) * target.size.width * anchorX
            let visibleTopBefore = before.y + (1 - scale) * target.size.height * anchorY

            XCTAssertTrue(timeline.materializeFontScaleSettle(at: 10.07) { _ in target })
            let after = try XCTUnwrap(timeline.active.first)
            XCTAssertEqual(after.startX, before.startX, accuracy: 0.001)
            XCTAssertEqual(after.y, before.y, accuracy: 0.001)
            XCTAssertEqual(after.glyphScale, scale, accuracy: 0.001)
            XCTAssertEqual(after.startX + (1 - after.glyphScale) * target.size.width * anchorX,
                           visibleLeftBefore, accuracy: 0.001)
            XCTAssertEqual(after.y + (1 - after.glyphScale) * target.size.height * anchorY,
                           visibleTopBefore, accuracy: 0.001)
            XCTAssertFalse(timeline.hasActiveFontScaleSettle(at: 10.07))
        }
    }
}
