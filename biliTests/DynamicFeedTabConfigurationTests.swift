import XCTest
@testable import bili

@MainActor
final class DynamicFeedTabConfigurationTests: XCTestCase {

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "cc.bili.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    func testDefaultConfigurationKeepsAllKindsInDefaultOrder() {
        let store = LibraryStore(userDefaults: makeUserDefaults())
        XCTAssertEqual(store.visibleDynamicFeedKinds, DynamicFeedKind.defaultOrder)
        XCTAssertEqual(
            store.visibleDynamicFeedKinds,
            [.all, .video, .pgc, .article, .up]
        )
    }

    func testStoredConfigurationNormalizesUnknownAndDuplicateValues() {
        let defaults = makeUserDefaults()
        defaults.set(["video", "unknown", "video", "up"], forKey: "cc.bili.display.visibleDynamicFeedKinds.v1")
        let store = LibraryStore(userDefaults: defaults)
        // Unknown values drop, duplicates collapse; kinds missing from the
        // stored list stay hidden.
        XCTAssertEqual(store.visibleDynamicFeedKinds, [.video, .up])
    }

    func testEmptyStoredConfigurationFallsBackToDefaultOrder() {
        let defaults = makeUserDefaults()
        defaults.set([], forKey: "cc.bili.display.visibleDynamicFeedKinds.v1")
        XCTAssertEqual(
            LibraryStore(userDefaults: defaults).visibleDynamicFeedKinds,
            DynamicFeedKind.defaultOrder
        )
        defaults.set(["unknown"], forKey: "cc.bili.display.visibleDynamicFeedKinds.v1")
        XCTAssertEqual(
            LibraryStore(userDefaults: defaults).visibleDynamicFeedKinds,
            DynamicFeedKind.defaultOrder
        )
    }

    func testHidingKindKeepsRemainingOrderAndPersistsAcrossInstances() {
        let defaults = makeUserDefaults()
        let store = LibraryStore(userDefaults: defaults)
        store.setDynamicFeedTab(.video, isVisible: false)
        XCTAssertEqual(store.visibleDynamicFeedKinds, [.all, .pgc, .article, .up])
        XCTAssertEqual(
            LibraryStore(userDefaults: defaults).visibleDynamicFeedKinds,
            [.all, .pgc, .article, .up]
        )
    }

    func testCannotHideLastVisibleKind() {
        let defaults = makeUserDefaults()
        let store = LibraryStore(userDefaults: defaults)
        for kind in DynamicFeedKind.defaultOrder where kind != .article {
            store.setDynamicFeedTab(kind, isVisible: false)
        }
        XCTAssertEqual(store.visibleDynamicFeedKinds, [.article])
        store.setDynamicFeedTab(.article, isVisible: false)
        XCTAssertEqual(store.visibleDynamicFeedKinds, [.article])
        XCTAssertEqual(LibraryStore(userDefaults: defaults).visibleDynamicFeedKinds, [.article])
    }

    func testShowingHiddenKindInsertsByDefaultOrder() {
        let defaults = makeUserDefaults()
        let store = LibraryStore(userDefaults: defaults)
        store.setDynamicFeedTab(.pgc, isVisible: false)
        store.setDynamicFeedTab(.all, isVisible: false)
        store.setDynamicFeedTab(.up, isVisible: false)
        XCTAssertEqual(store.visibleDynamicFeedKinds, [.video, .article])

        // .all sits before .video and .pgc before .article in the default order.
        store.setDynamicFeedTab(.pgc, isVisible: true)
        XCTAssertEqual(store.visibleDynamicFeedKinds, [.video, .pgc, .article])
        store.setDynamicFeedTab(.all, isVisible: true)
        XCTAssertEqual(store.visibleDynamicFeedKinds, [.all, .video, .pgc, .article])
    }

    func testMoveUpdatesOrderAndPersists() {
        let defaults = makeUserDefaults()
        let store = LibraryStore(userDefaults: defaults)
        // Move the trailing "UP" segment to the front — the same IndexSet/offset
        // contract SwiftUI's native .onMove delivers.
        store.moveDynamicFeedKinds(fromOffsets: IndexSet(integer: 4), toOffset: 0)
        XCTAssertEqual(store.visibleDynamicFeedKinds, [.up, .all, .video, .pgc, .article])
        XCTAssertEqual(
            LibraryStore(userDefaults: defaults).visibleDynamicFeedKinds,
            [.up, .all, .video, .pgc, .article]
        )
    }

    func testResetRestoresDefaultOrder() {
        let defaults = makeUserDefaults()
        let store = LibraryStore(userDefaults: defaults)
        store.setDynamicFeedTab(.all, isVisible: false)
        store.moveDynamicFeedKinds(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        XCTAssertNotEqual(store.visibleDynamicFeedKinds, DynamicFeedKind.defaultOrder)

        store.resetDynamicFeedTabs()
        XCTAssertEqual(store.visibleDynamicFeedKinds, DynamicFeedKind.defaultOrder)
        XCTAssertEqual(
            LibraryStore(userDefaults: defaults).visibleDynamicFeedKinds,
            DynamicFeedKind.defaultOrder
        )
    }

    func testNormalizedVisibleKindsNeverReturnsEmptyList() {
        XCTAssertEqual(DynamicFeedKind.normalizedVisibleKinds(nil), DynamicFeedKind.defaultOrder)
        XCTAssertEqual(DynamicFeedKind.normalizedVisibleKinds([]), DynamicFeedKind.defaultOrder)
        XCTAssertEqual(DynamicFeedKind.normalizedVisibleKinds(["unknown"]), DynamicFeedKind.defaultOrder)
        XCTAssertEqual(DynamicFeedKind.normalizedVisibleKinds(["all", "all", "unknown"]), [.all])
    }
}
