import Combine
import SwiftUI
import UIKit
import XCTest
@testable import bili

final class PlaybackDetailSharedLayoutTests: XCTestCase {
    @MainActor
    func testPortraitWidthUsesSmallestAvailableShortSide() {
        XCTAssertEqual(
            PlaybackDetailStableLayout.portraitWidth(
                containerSize: CGSize(width: 844, height: 390),
                fullscreenSize: CGSize(width: 852, height: 393),
                windowSize: CGSize(width: 375, height: 812)
            ),
            375
        )
    }

    @MainActor
    func testPortraitWidthWorksWithoutWindowSize() {
        XCTAssertEqual(
            PlaybackDetailStableLayout.portraitWidth(
                containerSize: CGSize(width: 393, height: 852),
                fullscreenSize: CGSize(width: 852, height: 393),
                windowSize: nil
            ),
            393
        )
    }

    @MainActor
    func testSharedPlayerAndContentMetrics() {
        XCTAssertEqual(PlaybackDetailPlayerMetrics.standardHeight(for: 393), 221.0625)
        XCTAssertEqual(PlaybackDetailContentMetrics.contentWidth(for: 393), 369)
        XCTAssertEqual(PlaybackDetailContentMetrics.contentWidth(for: 12), 0)
    }

    @MainActor
    func testUIKitShellLayoutUsesStandardPortraitPlayerAndContentFrames() {
        let layout = PlaybackDetailShellLayout(
            bounds: CGRect(x: 0, y: 0, width: 393, height: 852),
            safeAreaTop: 59,
            playerHeight: PlaybackDetailShellLayout.standardPlayerHeight(for: 393),
            contentTopInset: PlaybackDetailShellLayout.standardPlayerHeight(for: 393),
            usesFullscreenLayout: false
        )

        XCTAssertEqual(layout.playerFrame, CGRect(x: 0, y: 59, width: 393, height: 221))
        XCTAssertEqual(layout.contentFrame, CGRect(x: 0, y: 59, width: 393, height: 793))
        XCTAssertEqual(layout.contentTopInset, 221)
    }

    @MainActor
    func testUIKitShellLayoutMakesThePlayerTheOnlyLandscapeSurface() {
        let layout = PlaybackDetailShellLayout(
            bounds: CGRect(x: 0, y: 0, width: 852, height: 393),
            safeAreaTop: 0,
            playerHeight: 221,
            contentTopInset: 221,
            usesFullscreenLayout: true
        )

        XCTAssertEqual(layout.playerFrame, CGRect(x: 0, y: 0, width: 852, height: 393))
        XCTAssertEqual(layout.contentFrame, CGRect(x: 0, y: 393, width: 852, height: 393))
        XCTAssertNil(layout.contentTopInset)
    }

    func testRotationOptimizationDisabledPreservesVersion1021Behavior() {
        let policy = VideoDetailRotationOptimizationPolicy(isEnabled: false)

        XCTAssertTrue(policy.hidesContentHost(duringTransitionToLandscape: true))
        XCTAssertFalse(policy.hidesContentHost(duringTransitionToLandscape: false))
        XCTAssertTrue(policy.publishesContentLayoutDuringSystemTransition)
        XCTAssertFalse(
            policy.restoresPortraitAfterResolvingPortraitVideo(isCurrentlyLandscape: true)
        )
        XCTAssertEqual(
            policy.preferredLandscapeInterfaceOrientation(
                currentInterfaceOrientation: .portrait,
                deviceOrientation: .landscapeRight
            ),
            .landscapeRight
        )
    }

    func testRotationOptimizationFreezesContentAndUsesDeviceDirection() {
        let policy = VideoDetailRotationOptimizationPolicy(isEnabled: true)

        XCTAssertTrue(policy.hidesContentHost(duringTransitionToLandscape: true))
        XCTAssertTrue(policy.hidesContentHost(duringTransitionToLandscape: false))
        XCTAssertFalse(policy.publishesContentLayoutDuringSystemTransition)
        XCTAssertTrue(
            policy.restoresPortraitAfterResolvingPortraitVideo(isCurrentlyLandscape: true)
        )
        XCTAssertEqual(
            policy.preferredLandscapeInterfaceOrientation(
                currentInterfaceOrientation: .portrait,
                deviceOrientation: .landscapeLeft
            ),
            .landscapeRight
        )
        XCTAssertEqual(
            policy.preferredLandscapeInterfaceOrientation(
                currentInterfaceOrientation: .portrait,
                deviceOrientation: .landscapeRight
            ),
            .landscapeLeft
        )
    }

    @MainActor
    func testPageLifecycleActionsDeliverPageAndSceneEvents() {
        var events = [String]()
        let actions = PlaybackDetailPageLifecycleActions(
            onAppear: {
                events.append("appear")
            },
            onScenePhaseChanged: { phase in
                events.append("scene=\(phase)")
            },
            onDisappear: {
                events.append("disappear")
            }
        )

        actions.handleAppear()
        actions.handleScenePhaseChanged(.background)
        actions.handleScenePhaseChanged(.active)
        actions.handleDisappear()

        XCTAssertEqual(
            events,
            ["appear", "scene=background", "scene=active", "disappear"]
        )
    }

    @MainActor
    func testPGCPerformanceContextKeepsSeasonIdentityAcrossEpisodeSwitches() {
        let firstEpisode = makeVideo(bvid: "BV-first", seasonID: 46089, episodeID: 1)
        let secondEpisode = makeVideo(bvid: "BV-second", seasonID: 46089, episodeID: 2)
        let firstContext = PlaybackDetailPerformanceContext.video(firstEpisode)
        let secondContext = PlaybackDetailPerformanceContext.video(secondEpisode)

        XCTAssertEqual(firstContext.kind, .pgc)
        XCTAssertEqual(firstContext.pageID, "season-46089")
        XCTAssertEqual(firstContext.key, secondContext.key)
        XCTAssertNotEqual(firstContext.mediaID, secondContext.mediaID)
    }

    @MainActor
    func testFullscreenGeometryFallsBackToSafeAreaExpansion() {
        let geometry = PlaybackDetailFullscreenGeometry.resolve(
            containerSize: CGSize(width: 375, height: 734),
            safeAreaInsets: EdgeInsets(top: 47, leading: 0, bottom: 34, trailing: 0),
            localFrame: .zero,
            window: nil,
            resolveSize: { _, _ in
                XCTFail("Fallback geometry must not resolve a window size")
                return .zero
            }
        )

        XCTAssertEqual(geometry.size, CGSize(width: 375, height: 815))
        XCTAssertEqual(geometry.offset, CGSize(width: 0, height: -47))
    }

    @MainActor
    func testFullscreenGeometryUsesWindowCoordinateSpaceWhenAvailable() throws {
        let controller = UIViewController()
        let window = try makeWindow(frame: CGRect(x: 40, y: 30, width: 390, height: 844))
        window.rootViewController = controller
        window.layoutIfNeeded()

        let localFrame = CGRect(x: 84, y: 126, width: 300, height: 600)
        let frameInWindow = controller.view.convert(localFrame, from: nil)
        let expectedSize = CGSize(width: 844, height: 390)
        let geometry = PlaybackDetailFullscreenGeometry.resolve(
            containerSize: CGSize(width: 300, height: 600),
            safeAreaInsets: EdgeInsets(top: 10, leading: 5, bottom: 20, trailing: 5),
            localFrame: localFrame,
            window: window,
            resolveSize: { _, rootView in
                XCTAssertTrue(rootView === controller.view)
                return expectedSize
            }
        )

        XCTAssertEqual(geometry.size, expectedSize)
        XCTAssertEqual(
            geometry.offset,
            CGSize(width: -frameInWindow.minX, height: -frameInWindow.minY)
        )
    }

    @MainActor
    func testLoadedPageRemovesInitialContentAfterLoadedContentAppears() async throws {
        let model = PlaybackDetailLoadedValueModel()
        let recorder = PlaybackDetailLifecycleRecorder()
        let controller = UIHostingController(
            rootView: PlaybackDetailLoadedStateHarness(model: model, recorder: recorder)
        )
        let window = try makeWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        try await waitUntil { recorder.events.contains("initial appeared") }

        model.value = 1

        try await waitUntil {
            recorder.events.contains("loaded appeared")
                && recorder.events.contains("initial disappeared")
        }

        let loadedIndex = try XCTUnwrap(recorder.events.firstIndex(of: "loaded appeared"))
        let initialDisappearIndex = try XCTUnwrap(recorder.events.firstIndex(of: "initial disappeared"))
        XCTAssertLessThan(loadedIndex, initialDisappearIndex)
    }

    @MainActor
    func testPerformanceMonitorDeduplicatesMilestonesButKeepsRotationEvents() {
        let monitor = PlaybackDetailPerformanceMonitor.shared
        let context = PlaybackDetailPerformanceContext.live(roomID: 6, title: "直播测试")
        monitor.resetForTesting()
        defer { monitor.resetForTesting() }

        monitor.begin(context)
        monitor.mark(.loadedContentAppeared, context: context)
        monitor.mark(.loadedContentAppeared, context: context)
        monitor.mark(.fullscreenTransitionStarted, context: context, detail: "to=landscape")
        monitor.mark(.fullscreenTransitionStarted, context: context, detail: "to=portrait")
        let updatedContext = PlaybackDetailPerformanceContext.live(roomID: 6, title: "已加载直播标题")
        monitor.mark(.playerAttached, context: updatedContext)

        let snapshot = monitor.snapshot(for: context)
        XCTAssertEqual(
            snapshot?.events.filter { $0.milestone == .loadedContentAppeared }.count,
            1
        )
        XCTAssertEqual(
            snapshot?.events.filter { $0.milestone == .fullscreenTransitionStarted }.count,
            2
        )

        monitor.end(context)
        XCTAssertEqual(monitor.recentSnapshots().first?.events.last?.milestone, .pageDisappeared)
        XCTAssertEqual(monitor.recentSnapshots().first?.context.title, "已加载直播标题")
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else {
                XCTFail("Timed out waiting for shared playback detail state")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @MainActor
    private func makeWindow(frame: CGRect) throws -> UIWindow {
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let window = UIWindow(windowScene: scene)
        window.frame = frame
        return window
    }

    private func makeVideo(bvid: String, seasonID: Int, episodeID: Int) -> VideoItem {
        VideoItem(
            bvid: bvid,
            aid: nil,
            title: "测试番剧",
            pic: nil,
            desc: nil,
            duration: nil,
            pubdate: nil,
            owner: nil,
            stat: nil,
            cid: nil,
            pages: nil,
            dimension: nil,
            pgcSeasonID: seasonID,
            pgcEpisodeID: episodeID
        )
    }
}

@MainActor
private final class PlaybackDetailLoadedValueModel: ObservableObject {
    @Published var value: Int?
}

@MainActor
private final class PlaybackDetailLifecycleRecorder {
    private(set) var events: [String] = []

    func record(_ event: String) {
        events.append(event)
    }
}

private struct PlaybackDetailLoadedStateHarness: View {
    @ObservedObject var model: PlaybackDetailLoadedValueModel
    let recorder: PlaybackDetailLifecycleRecorder

    var body: some View {
        PlaybackDetailLoadedStatePage(model.value) { _ in
            Color.green
                .onAppear { recorder.record("loaded appeared") }
        } initialContent: {
            Color.gray
                .onAppear { recorder.record("initial appeared") }
                .onDisappear { recorder.record("initial disappeared") }
        }
    }
}
