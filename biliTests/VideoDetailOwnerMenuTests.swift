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

    func testFiveColumnsFitNarrowAndWideContent() {
        let widths: [CGFloat] = [220, 320, 390, 768]
        for width in widths {
            let layout = VideoDetailActionStripLayout(contentWidth: width)
            XCTAssertEqual(layout.avatarColumnWidth, layout.columnWidth)
            XCTAssertEqual(layout.columnWidth * 5 + layout.columnSpacing * 4, width, accuracy: 0.001)
            XCTAssertGreaterThan(layout.columnWidth, 0)
            XCTAssertGreaterThanOrEqual(layout.columnSpacing, 0)
        }
    }
}
