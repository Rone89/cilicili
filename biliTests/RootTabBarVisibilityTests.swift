import Combine
import SwiftUI
import UIKit
import XCTest
@testable import bili

@MainActor
final class RootTabBarVisibilityTests: XCTestCase {
    func testSingleVisibleRootTabHidesTabBarAndMultiTabRestoresIt() async throws {
        let deps = AppDependencies()
        deps.libraryStore.resetVisibleRootTabs()
        defer { deps.libraryStore.resetVisibleRootTabs() }

        let rootView = RootTabView()
            .nativeBottomScrollEdgeBlur()
            .environmentObject(deps)
            .environmentObject(deps.sessionStore)
            .environmentObject(deps.libraryStore)
            .environmentObject(deps.homeRecommendDiagnosticsStore)

        let window = try makeHostedWindow(rootView: rootView)
        defer { tearDownWindow(window) }

        try await Task.sleep(for: .milliseconds(600))
        let initialTBC = try XCTUnwrap(findTabBarController(in: window.rootViewController))
        XCTAssertFalse(initialTBC.isTabBarHidden)

        for tab in AppTab.defaultVisibleTabs where tab != .home {
            deps.libraryStore.setRootTab(tab, isVisible: false)
        }
        await waitUntil(timeout: 2.0) {
            self.findTabBarController(in: window.rootViewController)?.isTabBarHidden ?? true
        }
        if let singleTBC = findTabBarController(in: window.rootViewController) {
            XCTAssertTrue(singleTBC.isTabBarHidden)
        }

        deps.libraryStore.resetVisibleRootTabs()
        await waitUntil(timeout: 2.0) {
            self.findTabBarController(in: window.rootViewController)?.isTabBarHidden == false
        }
        let restoredTBC = try XCTUnwrap(findTabBarController(in: window.rootViewController))
        XCTAssertFalse(restoredTBC.isTabBarHidden)
    }

    func testNestedDetailPushAndPopPreservesTabBarVisibilityLifecycle() async throws {
        final class Driver: ObservableObject {
            @Published var path: [String] = []
        }
        struct Host: View {
            @ObservedObject var driver: Driver
            var body: some View {
                TabView {
                    Tab("首页", systemImage: "house") {
                        NavigationStack(path: $driver.path) {
                            ScrollView { Text("Root").frame(height: 2000) }
                                .navigationDestination(for: String.self) { value in
                                    if value == "level1" {
                                        Text("Level 1")
                                    } else {
                                        Text("Level 2")
                                    }
                                }
                        }
                        .coordinatesRootTabBarTransitions(
                            isDetailPresented: !driver.path.isEmpty,
                            hidesRootTabBar: false
                        )
                    }
                }
                .tabBarMinimizeBehavior(.onScrollDown)
            }
        }

        let driver = Driver()
        let window = try makeHostedWindow(rootView: Host(driver: driver))
        defer { tearDownWindow(window) }

        await waitUntil(timeout: 2.0) {
            self.findTabBarController(in: window.rootViewController) != nil
        }
        let tabBarController = try XCTUnwrap(findTabBarController(in: window.rootViewController))
        XCTAssertFalse(tabBarController.isTabBarHidden)
        XCTAssertEqual(tabBarController.tabBarMinimizeBehavior, .onScrollDown)

        driver.path.append("level1")
        await waitUntil(timeout: 2.0) { tabBarController.isTabBarHidden }
        XCTAssertTrue(tabBarController.isTabBarHidden)

        driver.path.append("level2")
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertTrue(tabBarController.isTabBarHidden)

        driver.path.removeLast()
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertTrue(tabBarController.isTabBarHidden)

        driver.path.removeLast()
        await waitUntil(timeout: 2.0) { !tabBarController.isTabBarHidden }
        XCTAssertFalse(tabBarController.isTabBarHidden)
        XCTAssertEqual(tabBarController.tabBarMinimizeBehavior, .onScrollDown)
    }

    func testDetailPopRevealsTabBarDuringTransitionInsteadOfSnappingAfterCompletion() async throws {
        final class Driver: ObservableObject {
            @Published var path: [String] = []
        }
        struct Host: View {
            @ObservedObject var driver: Driver
            var body: some View {
                TabView {
                    Tab("首页", systemImage: "house") {
                        NavigationStack(path: $driver.path) {
                            ScrollView { Text("Root").frame(height: 2000) }
                                .navigationDestination(for: String.self) { _ in
                                    ScrollView { Text("Detail").frame(height: 2000) }
                                }
                        }
                        .coordinatesRootTabBarTransitions(
                            isDetailPresented: !driver.path.isEmpty,
                            hidesRootTabBar: false
                        )
                    }
                }
                .tabBarMinimizeBehavior(.onScrollDown)
            }
        }

        let driver = Driver()
        let window = try makeHostedWindow(rootView: Host(driver: driver))
        defer { tearDownWindow(window) }

        await waitUntil(timeout: 2.0) {
            self.findTabBarController(in: window.rootViewController) != nil
        }
        let tbc = try XCTUnwrap(findTabBarController(in: window.rootViewController))
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNotNil(tbc.value(forKey: "_observingScrollView"))

        driver.path.append("detail")
        await waitUntil(timeout: 2.0) { tbc.isTabBarHidden }
        XCTAssertTrue(tbc.isTabBarHidden)
        try await Task.sleep(for: .milliseconds(450))

        driver.path.removeLast()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(tbc.isTabBarHidden, "返回转场开始后即应由 setTabBarHidden 恢复，不等到转场结束才闪现")
        try await Task.sleep(for: .milliseconds(500))

        XCTAssertFalse(tbc.isTabBarHidden)
        XCTAssertEqual(tbc.tabBar.alpha, 1.0, accuracy: 0.01)
        XCTAssertEqual(tbc.tabBarMinimizeBehavior, .onScrollDown)
        XCTAssertNotNil(
            tbc.value(forKey: "_observingScrollView"),
            "不混用 .toolbarVisibility(.hidden, for: .tabBar) 时，返回后必须完整保留 _observingScrollView"
        )
    }

    private func waitUntil(timeout: TimeInterval, condition: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func makeHostedWindow<Content: View>(rootView: Content) throws -> UIWindow {
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: rootView)
        window.makeKeyAndVisible()
        return window
    }

    private func tearDownWindow(_ window: UIWindow) {
        window.isHidden = true
        window.rootViewController = nil
    }

    private func findTabBarController(in viewController: UIViewController?) -> UITabBarController? {
        guard let viewController else { return nil }
        if let tabBarController = viewController as? UITabBarController { return tabBarController }
        for child in viewController.children {
            if let found = findTabBarController(in: child) { return found }
        }
        return nil
    }
}
