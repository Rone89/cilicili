import Foundation
import XCTest

@testable import bili

@MainActor
final class ScrollableTabHeadersExperimentTests: XCTestCase {
    func testScrollableTabHeadersDefaultOnAndPersistSelection() {
        let suiteName = "cc.bili.tests.scrollable-tab-headers.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = LibraryStore(userDefaults: defaults)
        XCTAssertTrue(store.scrollableTabHeadersExperimentEnabled)

        store.setScrollableTabHeadersExperimentEnabled(false)
        XCTAssertFalse(LibraryStore(userDefaults: defaults).scrollableTabHeadersExperimentEnabled)

        store.setScrollableTabHeadersExperimentEnabled(true)
        XCTAssertTrue(LibraryStore(userDefaults: defaults).scrollableTabHeadersExperimentEnabled)
    }
}
