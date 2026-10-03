import SwiftUI
import UIKit
import XCTest
@testable import bili

final class NavigationHistoryTests: XCTestCase {
    @MainActor
    func testActualStackHistoryExcludesCurrentAndOrdersNearestFirst() {
        let (history, navigation, pages) = makeStack(["首页", "A", "B", "C"])
        withExtendedLifetime(navigation) {
            XCTAssertEqual(history.entries.map(\.title), ["B", "A", "首页"])
            XCTAssertEqual(history.entries.map(\.depth), [2, 1, 0])
            XCTAssertEqual(history.entries.map(\.id), [pages[2], pages[1], pages[0]].map(ObjectIdentifier.init))
        }
    }

    @MainActor
    func testPopMutatesOnlyPathSuffixAndRetainsOriginalRouteValues() {
        let (history, navigation, _) = makeStack(["首页", "A", "B", "C"])
        let original = [UUID(), UUID(), UUID()]
        var path = NavigationPath(original)
        let context = NavigationHistoryContext(controller: history,
            path: Binding(get: { path }, set: { path = $0 }), rootTitle: "首页")
        withExtendedLifetime(navigation) {
            context.pop(to: history.entries[0])
            XCTAssertEqual(path, NavigationPath(Array(original.prefix(2))))
        }
    }

    @MainActor
    func testMultiLevelPopUsesDepthAndKeepsOriginalPrefix() {
        let (history, navigation, _) = makeStack(["首页", "A", "B", "C"])
        let original = [UUID(), UUID(), UUID()]
        var path = NavigationPath(original)
        let context = NavigationHistoryContext(controller: history,
            path: Binding(get: { path }, set: { path = $0 }), rootTitle: "首页")
        withExtendedLifetime(navigation) {
            context.pop(to: history.entries[1])
            XCTAssertEqual(path, NavigationPath([original[0]]))
        }
    }

    @MainActor
    func testRootPopAndShortTap() {
        let (history, navigation, _) = makeStack(["首页", "A", "B"])
        var path = NavigationPath([1, 2])
        let context = NavigationHistoryContext(controller: history,
            path: Binding(get: { path }, set: { path = $0 }), rootTitle: "首页")
        withExtendedLifetime(navigation) {
            context.pop(to: history.entries.last!)
            XCTAssertTrue(path.isEmpty)
            context.popOne()
            XCTAssertTrue(path.isEmpty)
            path.append(1)
            context.popOne()
            XCTAssertTrue(path.isEmpty)
        }
    }

    @MainActor
    func testDuplicateTitlesHaveDistinctIdentityAndDepth() {
        let (history, navigation, _) = makeStack(["首页", "同名", "同名", "C"])
        withExtendedLifetime(navigation) {
            let entries = history.entries
            XCTAssertEqual(entries[0].title, entries[1].title)
            XCTAssertNotEqual(entries[0].id, entries[1].id)
            XCTAssertEqual(history.removalCount(to: entries[0], pathDepth: 3), 1)
            XCTAssertEqual(history.removalCount(to: entries[1], pathDepth: 3), 2)
        }
    }

    @MainActor
    func testFullTitleAndMixedHistoryArePreserved() {
        let longTitle = String(repeating: "这是一个完整标题", count: 30)
        let (history, navigation, _) = makeStack(["搜索", "搜索结果", "某 UP 主空间", longTitle, "B"])
        withExtendedLifetime(navigation) {
            XCTAssertEqual(history.entries.map(\.title), [longTitle, "某 UP 主空间", "搜索结果", "搜索"])
        }
    }

    @MainActor
    func testStaleSelectionCannotPopReplacementAtSameDepth() {
        let (history, navigation, _) = makeStack(["首页", "A", "B", "C"])
        let oldEntry = history.entries[0]
        navigation.setViewControllers([UIViewController(), UIViewController(), UIViewController(), UIViewController()], animated: false)
        XCTAssertNil(history.removalCount(to: oldEntry, pathDepth: 3))
    }

    @MainActor
    func testMismatchedControllerStackDoesNotInventHistory() {
        let (history, navigation, _) = makeStack(["首页", "A", "B"])
        withExtendedLifetime(navigation) {
            history.refresh(pathDepth: 4, rootTitle: "首页")
            XCTAssertTrue(history.entries.isEmpty)
        }
    }

    @MainActor
    func testSystemPopRefreshRemovesDepartedEntries() {
        let (history, navigation, _) = makeStack(["首页", "A", "B", "C"])
        navigation.popViewController(animated: false)
        history.refresh(pathDepth: 2, rootTitle: "首页")
        XCTAssertEqual(history.entries.map(\.title), ["A", "首页"])
    }

    @MainActor
    func testDisabledResetReleasesHistoryAndDoesNotOwnNavigationController() {
        let history = NavigationHistoryController()
        weak var weakNavigation: UINavigationController?
        autoreleasepool {
            let root = UIViewController()
            let navigation = UINavigationController(rootViewController: root)
            weakNavigation = navigation
            history.register(title: "首页", controller: root, in: navigation)
        }
        XCTAssertNil(weakNavigation)
        history.reset()
        XCTAssertTrue(history.entries.isEmpty)
        XCTAssertNil(history.navigationController)
    }

    @MainActor
    func testDisableRejectsLateTitleRegistrationAndOldMenuActions() {
        let (history, navigation, pages) = makeStack(["首页", "A", "B"])
        let oldEntry = history.entries[0]
        history.setEnabled(false)
        history.register(title: "late", controller: pages[1], in: navigation)
        history.refresh(pathDepth: 2, rootTitle: "首页")
        XCTAssertTrue(history.entries.isEmpty)
        XCTAssertNil(history.navigationController)
        XCTAssertNil(history.removalCount(to: oldEntry, pathDepth: 2))
    }

    @MainActor
    func testFlagDefaultsOffAndPersistsWithoutChangingRoutes() {
        let suite = "HistoryBackTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LibraryStore(userDefaults: defaults)
        XCTAssertFalse(store.videoDetailBottomHistoryBackButtonExperimentEnabled)
        store.setVideoDetailBottomHistoryBackButtonExperimentEnabled(true)
        XCTAssertTrue(LibraryStore(userDefaults: defaults).videoDetailBottomHistoryBackButtonExperimentEnabled)
        store.setVideoDetailBottomHistoryBackButtonExperimentEnabled(false)
        XCTAssertFalse(LibraryStore(userDefaults: defaults).videoDetailBottomHistoryBackButtonExperimentEnabled)
    }

    @MainActor
    private func makeStack(_ titles: [String]) -> (NavigationHistoryController, UINavigationController, [UIViewController]) {
        let pages = titles.map { _ in UIViewController() }
        let navigation = UINavigationController()
        navigation.setViewControllers(pages, animated: false)
        let history = NavigationHistoryController()
        for (page, title) in zip(pages, titles) { history.register(title: title, controller: page, in: navigation) }
        history.refresh(pathDepth: pages.count - 1, rootTitle: titles[0])
        return (history, navigation, pages)
    }
}
