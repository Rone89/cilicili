import XCTest
@testable import bili

@MainActor
final class VideoDetailOwnerMenuTests: XCTestCase {
    func testRetiredExperimentPreferenceIsRemovedForEitherValue() {
        for enabled in [false, true] {
            let suite = "owner-menu-tests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let key = "cc.bili.experimental.videoDetailOwnerMenu.v1"
            defaults.set(enabled, forKey: key)

            _ = LibraryStore(userDefaults: defaults)
            XCTAssertNil(defaults.object(forKey: key))
        }
    }

    func testActionStripUsesCompactLeftAlignedGeometryWithoutOverflow() {
        let widths: [CGFloat] = [160, 220, 226, 240, 320, 390, 768]
        for width in widths {
            let layout = VideoDetailActionStripLayout(contentWidth: width)
            XCTAssertEqual(layout.avatarColumnWidth, layout.columnWidth)
            XCTAssertLessThanOrEqual(layout.contentGroupWidth, width + 0.001)
            XCTAssertGreaterThan(layout.columnWidth, 0)
            XCTAssertGreaterThanOrEqual(layout.avatarActionSpacing, layout.actionSpacing)
            XCTAssertLessThanOrEqual(layout.avatarActionSpacing, 20)
            XCTAssertLessThanOrEqual(layout.actionSpacing, 12)
        }

        let wideLayout = VideoDetailActionStripLayout(contentWidth: 390)
        XCTAssertEqual(wideLayout.avatarActionSpacing, 20)
        XCTAssertEqual(wideLayout.actionSpacing, 12)
        XCTAssertLessThan(wideLayout.contentGroupWidth, wideLayout.contentWidth)
    }
}
