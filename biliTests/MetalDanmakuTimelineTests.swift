import Foundation
import UIKit
import XCTest

@testable import bili

@MainActor
final class MetalDanmakuTimelineTests: XCTestCase {
    func testScrollingFramesUseAbsoluteMediaTime() throws {
        let timeline = makeTimeline(
            viewport: CGSize(width: 320, height: 200),
            settings: overlapSettings(displayArea: .full, trackHeight: 30),
            maximumActiveCount: 4
        )
        let item = makeItem(id: "scroll", time: 10, mode: 1)
        let size = CGSize(width: 80, height: 20)

        timeline.replaceItems([item], at: 10) { _ in size }
        let atStart = try XCTUnwrap(timeline.active.first)
        XCTAssertEqual(atStart.frame(at: 10).minX, 320, accuracy: 0.001)

        timeline.advance(to: 11) { _ in size }
        let atOneSecond = try XCTUnwrap(timeline.active.first)
        let speed = (320 + size.width) / 7.2
        XCTAssertEqual(atOneSecond.frame(at: 11).minX, 320 - speed, accuracy: 0.001)

        timeline.advance(to: 12) { _ in size }
        let atTwoSeconds = try XCTUnwrap(timeline.active.first)
        XCTAssertEqual(atTwoSeconds.frame(at: 12).minX, 320 - 2 * speed, accuracy: 0.001)
        XCTAssertEqual(atTwoSeconds.frame(at: 12).minX, atOneSecond.frame(at: 12).minX, accuracy: 0.001)

        let rebuilt = makeTimeline(
            viewport: CGSize(width: 320, height: 200),
            settings: overlapSettings(displayArea: .full, trackHeight: 30),
            maximumActiveCount: 4
        )
        rebuilt.replaceItems([item], at: 12) { _ in size }
        let rebuiltEntry = try XCTUnwrap(rebuilt.active.first)
        XCTAssertEqual(rebuiltEntry.frame(at: 12).minX, atTwoSeconds.frame(at: 12).minX, accuracy: 0.001)
    }

    func testTopAndBottomEntriesHonorInsetsAndPadding() throws {
        var settings = overlapSettings(displayArea: .full, trackHeight: 30)
        settings.danmakuKit.topPadding = 5
        settings.danmakuKit.bottomPadding = 7
        let timeline = makeTimeline(
            viewport: CGSize(width: 320, height: 180),
            settings: settings,
            topInset: 10,
            bottomInset: 20,
            maximumActiveCount: 4
        )
        let top = makeItem(id: "top", time: 5, mode: 5)
        let bottom = makeItem(id: "bottom", time: 5, mode: 4)
        let size = CGSize(width: 100, height: 30)

        timeline.replaceItems([top, bottom], at: 5) { _ in size }

        let topEntry = try XCTUnwrap(timeline.active.first { $0.item.id == "top" })
        let bottomEntry = try XCTUnwrap(timeline.active.first { $0.item.id == "bottom" })
        XCTAssertEqual(topEntry.frame(at: 5).minY, 15, accuracy: 0.001)
        XCTAssertEqual(bottomEntry.frame(at: 5).minY, 105, accuracy: 0.001)
        XCTAssertGreaterThan(bottomEntry.frame(at: 5).minY, topEntry.frame(at: 5).maxY)
        XCTAssertLessThanOrEqual(bottomEntry.frame(at: 5).maxY, 180 - 20 - 7)
    }

    func testTypeEnableFlagsFilterUnsupportedItems() {
        var settings = overlapSettings(displayArea: .full, trackHeight: 30)
        let timeline = makeTimeline(
            viewport: CGSize(width: 320, height: 600),
            settings: settings,
            maximumActiveCount: 10
        )
        let items = [
            makeItem(id: "scroll", time: 2, mode: 1),
            makeItem(id: "top", time: 2, mode: 5),
            makeItem(id: "bottom", time: 2, mode: 4),
            makeItem(id: "unsupported", time: 2, mode: 6)
        ]

        timeline.replaceItems(items, at: 2) { _ in CGSize(width: 80, height: 20) }
        XCTAssertEqual(Set(timeline.active.map(\.item.id)), ["scroll", "top", "bottom"])

        settings.danmakuKit.enablesFloating = false
        timeline.settings = settings
        timeline.rebuild(at: 2) { _ in CGSize(width: 80, height: 20) }
        XCTAssertEqual(Set(timeline.active.map(\.item.id)), ["top", "bottom"])

        settings.danmakuKit.enablesTop = false
        timeline.settings = settings
        timeline.rebuild(at: 2) { _ in CGSize(width: 80, height: 20) }
        XCTAssertEqual(Set(timeline.active.map(\.item.id)), ["bottom"])

        settings.danmakuKit.enablesBottom = false
        timeline.settings = settings
        timeline.rebuild(at: 2) { _ in CGSize(width: 80, height: 20) }
        XCTAssertTrue(timeline.active.isEmpty)
    }

    func testDuplicateIDsAreAdmittedOnlyOnce() {
        let timeline = makeTimeline(
            viewport: CGSize(width: 320, height: 300),
            settings: overlapSettings(displayArea: .full, trackHeight: 30),
            maximumActiveCount: 10
        )
        let earlier = makeItem(id: "duplicate", time: 0, mode: 1)
        let later = makeItem(id: "duplicate", time: 1, mode: 1)

        timeline.replaceItems([later, earlier], at: 1) { _ in CGSize(width: 80, height: 20) }

        XCTAssertEqual(timeline.active.count, 1)
        XCTAssertEqual(timeline.active.first?.item.id, "duplicate")
        XCTAssertEqual(timeline.active.first?.item.time, 0)
    }

    func testEntriesExpireAtTheirEndTimeAndClearAllowsRebuild() {
        let timeline = makeTimeline(
            viewport: CGSize(width: 320, height: 300),
            settings: overlapSettings(displayArea: .full, trackHeight: 30),
            maximumActiveCount: 4
        )
        let item = makeItem(id: "expiring", time: 0, mode: 5)
        let measure: (DanmakuItem) -> CGSize? = { _ in CGSize(width: 80, height: 20) }

        timeline.replaceItems([item], at: 0, measure: measure)
        XCTAssertEqual(timeline.active.count, 1)

        timeline.advance(to: 1, measure: measure)
        timeline.advance(to: 2, measure: measure)
        timeline.advance(to: 3, measure: measure)
        timeline.advance(to: 4, measure: measure)
        XCTAssertEqual(timeline.active.count, 1)

        timeline.advance(to: 4.2, measure: measure)
        XCTAssertTrue(timeline.active.isEmpty)

        timeline.clear()
        XCTAssertTrue(timeline.active.isEmpty)
        timeline.rebuild(at: 0, measure: measure)
        XCTAssertEqual(timeline.active.map(\.item.id), ["expiring"])
    }

    func testForwardAndBackwardSeeksRebuildTheTimeline() {
        let timeline = makeTimeline(
            viewport: CGSize(width: 320, height: 300),
            settings: overlapSettings(displayArea: .full, trackHeight: 30),
            maximumActiveCount: 10
        )
        let old = makeItem(id: "old", time: 0, mode: 5)
        let current = makeItem(id: "current", time: 4, mode: 1)
        let future = makeItem(id: "future", time: 6, mode: 1)
        let measure: (DanmakuItem) -> CGSize? = { _ in CGSize(width: 80, height: 20) }

        timeline.replaceItems([old, current, future], at: 0, measure: measure)
        XCTAssertEqual(Set(timeline.active.map(\.item.id)), ["old"])

        timeline.advance(to: 5, measure: measure)
        XCTAssertEqual(Set(timeline.active.map(\.item.id)), ["current"])

        timeline.advance(to: 1, measure: measure)
        XCTAssertEqual(Set(timeline.active.map(\.item.id)), ["old"])
    }

    func testWindowRefreshPreservesInFlightEntries() {
        let settings = overlapSettings(displayArea: .full, trackHeight: 30)
        let oldItems = makeItems(count: 24, time: 10, mode: 1)
        let lateItems = (0..<6).map { makeItem(id: "late-\($0)", time: 10.25, mode: 1) }
        let refreshedItems = oldItems + lateItems
        let size = CGSize(width: 80, height: 20)
        let measure: (DanmakuItem) -> CGSize? = { _ in size }

        let timeline = makeTimeline(
            viewport: CGSize(width: 320, height: 300),
            settings: settings,
            maximumActiveCount: 24
        )
        timeline.replaceItems(oldItems, at: 10, measure: measure)
        timeline.advance(to: 10.5, measure: measure)
        let activeBeforeRefresh = Set(timeline.active.map(\.item.id))
        XCTAssertEqual(activeBeforeRefresh.count, 24)

        XCTAssertTrue(timeline.canPreserveActiveEntries(with: refreshedItems, at: 10.5))
        XCTAssertTrue(timeline.replaceItemsPreservingActive(refreshedItems, at: 10.5))

        XCTAssertEqual(Set(timeline.active.map(\.item.id)), activeBeforeRefresh)
        XCTAssertEqual(timeline.active.count, 24)

        let rebuilt = makeTimeline(
            viewport: CGSize(width: 320, height: 300),
            settings: settings,
            maximumActiveCount: 24
        )
        rebuilt.replaceItems(oldItems, at: 10, measure: measure)
        rebuilt.replaceItems(refreshedItems, at: 10.5, measure: measure)
        XCTAssertLessThan(Set(rebuilt.active.map(\.item.id)).intersection(activeBeforeRefresh).count, 24)
    }

    func testWindowRefreshDoesNotPreserveEntriesAcrossSeekOrSourceChange() {
        let timeline = makeTimeline(
            viewport: CGSize(width: 320, height: 300),
            settings: overlapSettings(displayArea: .full, trackHeight: 30),
            maximumActiveCount: 10
        )
        let old = makeItem(id: "old", time: 10, mode: 1)
        let measure: (DanmakuItem) -> CGSize? = { _ in CGSize(width: 80, height: 20) }
        timeline.replaceItems([old], at: 10, measure: measure)

        XCTAssertFalse(timeline.canPreserveActiveEntries(with: [old], at: 20))
        XCTAssertFalse(timeline.canPreserveActiveEntries(with: [makeItem(id: "new", time: 10, mode: 1)], at: 10))
    }

    func testCollisionRejectsALaterWideItemThatWouldCatchUp() throws {
        let viewportWidth: CGFloat = 320
        let duration: CGFloat = 7.2
        let narrowSize = CGSize(width: 20, height: 20)
        let wideSize = CGSize(width: 160, height: 20)
        let settings = nonOverlappingSettings(displayArea: .full, trackHeight: 100)
        let timeline = makeTimeline(
            viewport: CGSize(width: viewportWidth, height: 100),
            settings: settings,
            maximumActiveCount: 10
        )
        let narrow = makeItem(id: "narrow", time: 0, mode: 1)
        let wide = makeItem(id: "wide", time: 2, mode: 1)
        let sizes = [narrow.id: narrowSize, wide.id: wideSize]

        timeline.replaceItems([narrow, wide], at: 2) { sizes[$0.id] }

        let admitted = try XCTUnwrap(timeline.active.first)
        XCTAssertEqual(admitted.item.id, "narrow")

        let narrowAtAdmission = admitted.frame(at: 2)
        let wideAtAdmission = CGRect(x: viewportWidth, y: narrowAtAdmission.minY,
                                     width: wideSize.width, height: wideSize.height)
        XCTAssertFalse(narrowAtAdmission.intersects(wideAtAdmission))

        let narrowAtExpiry = admitted.frame(at: admitted.endTime)
        let wideAtExpiry = CGRect(
            x: viewportWidth - (viewportWidth + wideSize.width) / duration
                * CGFloat(admitted.endTime - wide.time),
            y: narrowAtExpiry.minY,
            width: wideSize.width,
            height: wideSize.height
        )
        XCTAssertTrue(narrowAtExpiry.intersects(wideAtExpiry))
    }

    func testOverlapSettingChangesAdmissionForOverlappingItems() {
        var settings = nonOverlappingSettings(displayArea: .full, trackHeight: 100)
        let timeline = makeTimeline(
            viewport: CGSize(width: 320, height: 100),
            settings: settings,
            maximumActiveCount: 10
        )
        let items = [
            makeItem(id: "first", time: 0, mode: 1),
            makeItem(id: "second", time: 1, mode: 1)
        ]
        let measure: (DanmakuItem) -> CGSize? = { _ in CGSize(width: 100, height: 20) }

        timeline.replaceItems(items, at: 1, measure: measure)
        XCTAssertEqual(timeline.active.count, 1)

        settings.danmakuKit.allowsDanmakuOverlap = true
        timeline.settings = settings
        timeline.rebuild(at: 1, measure: measure)
        XCTAssertEqual(timeline.active.count, 2)
    }

    func testInvalidTimesAndMeasuredSizesAreIgnored() {
        let timeline = makeTimeline(
            viewport: CGSize(width: 320, height: 300),
            settings: overlapSettings(displayArea: .full, trackHeight: 30),
            maximumActiveCount: 20
        )
        let valid = makeItem(id: "valid", time: 0, mode: 1)
        let invalidItems = [
            makeItem(id: "nan-time", time: .nan, mode: 1),
            makeItem(id: "infinite-time", time: .infinity, mode: 1),
            makeItem(id: "nan-font-size", time: 0, mode: 1, fontSize: .nan),
            makeItem(id: "nan-size", time: 0, mode: 1),
            makeItem(id: "infinite-size", time: 0, mode: 1),
            makeItem(id: "zero-size", time: 0, mode: 1),
            makeItem(id: "negative-size", time: 0, mode: 1)
        ]
        let sizes: [String: CGSize] = [
            "valid": CGSize(width: 80, height: 20),
            "nan-size": CGSize(width: CGFloat.nan, height: 20),
            "infinite-size": CGSize(width: CGFloat.infinity, height: 20),
            "zero-size": .zero,
            "negative-size": CGSize(width: -1, height: 20)
        ]
        let measure: (DanmakuItem) -> CGSize? = { sizes[$0.id] }

        timeline.replaceItems([valid] + invalidItems, at: 0, measure: measure)
        XCTAssertEqual(timeline.active.map(\.item.id), ["valid"])

        timeline.advance(to: .nan, measure: measure)
        XCTAssertEqual(timeline.active.map(\.item.id), ["valid"])

        timeline.rebuild(at: .infinity, measure: measure)
        XCTAssertTrue(timeline.active.isEmpty)

        timeline.replaceItems([valid], at: .nan, measure: measure)
        XCTAssertTrue(timeline.active.isEmpty)

        for invalidViewport in [
            CGSize(width: CGFloat.nan, height: 300),
            CGSize(width: CGFloat.infinity, height: 300),
            CGSize(width: 0, height: 300),
            CGSize(width: 320, height: CGFloat.infinity),
            CGSize(width: 320, height: 0)
        ] {
            timeline.viewport = invalidViewport
            timeline.replaceItems([valid], at: 0, measure: measure)
            XCTAssertTrue(timeline.active.isEmpty)
        }
    }

    func testMaximumActiveCountCapsAdmissionAndRebuildUsesUpdatedCap() {
        let timeline = makeTimeline(
            viewport: CGSize(width: 320, height: 100),
            settings: overlapSettings(displayArea: .full, trackHeight: 100),
            maximumActiveCount: 3
        )
        let items = makeItems(count: 20, time: 8, mode: 1)
        let measure: (DanmakuItem) -> CGSize? = { _ in CGSize(width: 80, height: 20) }

        timeline.replaceItems(items, at: 8, measure: measure)
        XCTAssertEqual(timeline.active.count, 3)

        timeline.maximumActiveCount = 8
        timeline.rebuild(at: 8, measure: measure)
        XCTAssertEqual(timeline.active.count, 8)
    }

    func testActiveCountScenariosAreDeterministicAtOneMediaTime() {
        let mediaTime = 42.0
        let counts = [10, 50, 100, 300, 600]

        for count in counts {
            var roomySettings = DanmakuSettings.default
            roomySettings.danmakuKit.displayArea = .full
            roomySettings.danmakuKit.trackHeight = 10
            roomySettings.danmakuKit.allowsDanmakuOverlap = false
            let roomy = makeTimeline(
                viewport: CGSize(width: 1_000, height: 10_000),
                settings: roomySettings,
                maximumActiveCount: count
            )
            roomy.replaceItems(makeItems(count: count, time: mediaTime, mode: 1), at: mediaTime) { _ in
                CGSize(width: 80, height: 10)
            }
            XCTAssertEqual(roomy.active.count, count, "roomy fixture count \(count)")

            let overlap = makeTimeline(
                viewport: CGSize(width: 320, height: 100),
                settings: overlapSettings(displayArea: .full, trackHeight: 100),
                maximumActiveCount: count
            )
            overlap.replaceItems(makeItems(count: count, time: mediaTime, mode: 1), at: mediaTime) { _ in
                CGSize(width: 80, height: 20)
            }
            XCTAssertEqual(overlap.active.count, count, "overlap fixture count \(count)")
        }
    }

    private func makeTimeline(
        viewport: CGSize,
        settings: DanmakuSettings,
        topInset: CGFloat = 0,
        bottomInset: CGFloat = 0,
        maximumActiveCount: Int
    ) -> MetalDanmakuTimeline {
        let timeline = MetalDanmakuTimeline()
        timeline.viewport = viewport
        timeline.settings = settings
        timeline.topInset = topInset
        timeline.bottomInset = bottomInset
        timeline.maximumActiveCount = maximumActiveCount
        return timeline
    }

    private func overlapSettings(
        displayArea: DanmakuDisplayArea,
        trackHeight: Double
    ) -> DanmakuSettings {
        var settings = DanmakuSettings.default
        settings.danmakuKit.displayArea = displayArea
        settings.danmakuKit.trackHeight = trackHeight
        settings.danmakuKit.allowsDanmakuOverlap = true
        return settings
    }

    private func nonOverlappingSettings(
        displayArea: DanmakuDisplayArea,
        trackHeight: Double
    ) -> DanmakuSettings {
        var settings = overlapSettings(displayArea: displayArea, trackHeight: trackHeight)
        settings.danmakuKit.allowsDanmakuOverlap = false
        return settings
    }

    private func makeItems(count: Int, time: TimeInterval, mode: Int) -> [DanmakuItem] {
        (0..<count).map { index in
            makeItem(id: String(format: "item-%04d", index), time: time, mode: mode)
        }
    }

    private func makeItem(
        id: String,
        time: TimeInterval,
        mode: Int,
        fontSize: Double = 25
    ) -> DanmakuItem {
        DanmakuItem(
            id: id,
            time: time,
            mode: mode,
            fontSize: fontSize,
            color: 0xFFFFFF,
            text: id
        )
    }
}
