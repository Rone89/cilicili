import AVFoundation
import SwiftUI
import UIKit
import XCTest
@testable import bili

@MainActor
final class AdaptiveLayoutAndPlayerIdentityTests: XCTestCase {
    func testAdaptiveLayoutPolicyBreakpointsAndExperimentFallback() {
        XCTAssertEqual(
            AdaptiveLayoutPolicy.widthTier(containerSize: CGSize(width: 390, height: 844), horizontalSizeClass: .compact),
            .compact
        )
        XCTAssertEqual(
            AdaptiveLayoutPolicy.widthTier(containerSize: CGSize(width: 956, height: 440), horizontalSizeClass: .compact),
            .compact
        )
        XCTAssertEqual(
            AdaptiveLayoutPolicy.widthTier(containerSize: CGSize(width: 680, height: 800), horizontalSizeClass: .regular),
            .medium
        )
        XCTAssertEqual(
            AdaptiveLayoutPolicy.widthTier(containerSize: CGSize(width: 1024, height: 1366), horizontalSizeClass: .regular),
            .expanded
        )
        XCTAssertEqual(
            AdaptiveLayoutPolicy.widthTier(containerSize: CGSize(width: 1366, height: 1024), horizontalSizeClass: .regular),
            .wide
        )
        XCTAssertEqual(
            AdaptiveLayoutPolicy.widthTier(
                containerSize: CGSize(width: 1366, height: 1024),
                horizontalSizeClass: .regular,
                adaptiveEnabled: false
            ),
            .compact
        )
    }

    func testHomeFeedLayoutMetricsAdaptsColumnsWithoutAffectingCompact() {
        let compact = HomeFeedLayoutMetrics(
            mode: .doubleColumn,
            containerWidth: 390,
            viewportHeight: 844,
            horizontalSizeClass: .compact,
            adaptiveLargeScreenEnabled: true
        )
        XCTAssertEqual(compact.doubleColumns.count, 2)
        XCTAssertEqual(compact.feedHorizontalPadding, 20)
        XCTAssertNil(compact.maxContentWidth)

        let duoUnfolded = HomeFeedLayoutMetrics(
            mode: .doubleColumn,
            containerWidth: 744,
            viewportHeight: 1133,
            horizontalSizeClass: .regular,
            adaptiveLargeScreenEnabled: true
        )
        XCTAssertEqual(duoUnfolded.doubleColumns.count, 3)
        XCTAssertEqual(duoUnfolded.feedHorizontalPadding, 24)

        let ipadLandscape = HomeFeedLayoutMetrics(
            mode: .doubleColumn,
            containerWidth: 1366,
            viewportHeight: 1024,
            horizontalSizeClass: .regular,
            adaptiveLargeScreenEnabled: true
        )
        XCTAssertEqual(ipadLandscape.doubleColumns.count, 5)
        XCTAssertEqual(ipadLandscape.feedHorizontalPadding, 32)
        XCTAssertEqual(ipadLandscape.maxContentWidth, AdaptiveLayoutPolicy.multiColumnFeedMaxWidth)

        let disabled = HomeFeedLayoutMetrics(
            mode: .doubleColumn,
            containerWidth: 1366,
            viewportHeight: 1024,
            horizontalSizeClass: .regular,
            adaptiveLargeScreenEnabled: false
        )
        XCTAssertEqual(disabled.doubleColumns.count, 2)
    }

    func testVideoDetailShellLayoutResolvesTwoColumnSplitAndRevertsToCompact() {
        let compact = VideoDetailShellLayout.resolve(
            bounds: CGRect(x: 0, y: 0, width: 390, height: 844),
            safeAreaTop: 59,
            safeAreaBottom: 34,
            videoAspectRatio: 16.0 / 9.0,
            currentPlayerHeight: nil,
            isPlaybackActive: true,
            isLandscape: false,
            isPortraitFullscreen: false,
            horizontalSizeClass: .compact,
            adaptiveLargeScreenEnabled: true
        )
        XCTAssertEqual(compact.adaptiveMode, .compactStacked)
        XCTAssertEqual(compact.playerFrame.width, 390)
        XCTAssertEqual(compact.contentFrame.minX, 0)
        XCTAssertGreaterThan(compact.contentTopInset ?? 0, 200)

        let ipadPortrait = VideoDetailShellLayout.resolve(
            bounds: CGRect(x: 0, y: 0, width: 1024, height: 1366),
            safeAreaTop: 24,
            safeAreaBottom: 20,
            videoAspectRatio: 16.0 / 9.0,
            currentPlayerHeight: nil,
            isPlaybackActive: true,
            isLandscape: false,
            isPortraitFullscreen: false,
            horizontalSizeClass: .regular,
            adaptiveLargeScreenEnabled: true
        )
        XCTAssertEqual(ipadPortrait.adaptiveMode, .compactStacked)
        XCTAssertEqual(ipadPortrait.playerFrame.width, 1024)

        let split = VideoDetailShellLayout.resolve(
            bounds: CGRect(x: 0, y: 0, width: 1366, height: 1024),
            safeAreaTop: 24,
            safeAreaBottom: 20,
            videoAspectRatio: 16.0 / 9.0,
            currentPlayerHeight: nil,
            isPlaybackActive: true,
            isLandscape: false,
            isPortraitFullscreen: false,
            horizontalSizeClass: .regular,
            adaptiveLargeScreenEnabled: true
        )
        XCTAssertEqual(split.adaptiveMode, .twoColumnSplit)
        XCTAssertFalse(split.usesFullscreenLayout)
        XCTAssertEqual(split.contentTopInset, 0)
        XCTAssertEqual(split.contentFrame.minY, 0)
        XCTAssertEqual(split.contentFrame.height, 1024)
        XCTAssertEqual(split.playerFrame.minX, 0)
        XCTAssertGreaterThanOrEqual(split.playerFrame.width, 800)
        XCTAssertEqual(split.contentFrame.minX, split.playerFrame.width, accuracy: 0.5)
        XCTAssertEqual(split.contentFrame.width, 460, accuracy: 0.5)
        XCTAssertEqual(split.danmakuCanvasSize, split.playerFrame.size)

        let duoInnerLandscape = VideoDetailShellLayout.resolve(
            bounds: CGRect(x: 0, y: 0, width: 951, height: 669),
            safeAreaTop: 0,
            safeAreaBottom: 20,
            videoAspectRatio: 16.0 / 9.0,
            currentPlayerHeight: nil,
            isPlaybackActive: true,
            isLandscape: false,
            isPortraitFullscreen: false,
            horizontalSizeClass: .regular,
            adaptiveLargeScreenEnabled: true
        )
        XCTAssertEqual(duoInnerLandscape.adaptiveMode, .twoColumnSplit)
        XCTAssertEqual(duoInnerLandscape.contentFrame.minY, 0)
        XCTAssertEqual(duoInnerLandscape.contentFrame.height, 669)
        XCTAssertEqual(duoInnerLandscape.contentFrame.width, 380, accuracy: 0.5)

        let narrowSplit = VideoDetailShellLayout.resolve(
            bounds: CGRect(x: 0, y: 0, width: 500, height: 1024),
            safeAreaTop: 24,
            safeAreaBottom: 20,
            videoAspectRatio: 16.0 / 9.0,
            currentPlayerHeight: nil,
            isPlaybackActive: true,
            isLandscape: false,
            isPortraitFullscreen: false,
            horizontalSizeClass: .compact,
            adaptiveLargeScreenEnabled: true
        )
        XCTAssertEqual(narrowSplit.adaptiveMode, .compactStacked)
    }

    func testVideoDetailContainerPreservesPlayerAndSurfaceIdentityAcrossContinuousResizing() async throws {
        let mediaURL = try await makeLocalTestVideo()
        defer { try? FileManager.default.removeItem(at: mediaURL) }

        let dependencies = AppDependencies()
        let previousAdaptive = dependencies.libraryStore.adaptiveLargeScreenLayoutExperimentEnabled
        dependencies.libraryStore.setAdaptiveLargeScreenLayoutExperimentEnabled(true)
        defer { dependencies.libraryStore.setAdaptiveLargeScreenLayoutExperimentEnabled(previousAdaptive) }

        let video = try JSONDecoder.bili.decode(VideoItem.self, from: Data("""
            {"bvid":"BVAdaptiveIdentityProbe","title":"Adaptive identity probe","cid":101,"dimension":{"width":1920,"height":1080,"rotate":0}}
            """.utf8))
        let detailVM = VideoDetailViewModel(
            seedVideo: video,
            api: dependencies.api,
            libraryStore: dependencies.libraryStore,
            sessionStore: dependencies.sessionStore,
            sponsorBlockService: dependencies.sponsorBlockService
        )

        let engine = AVPlayerHLSBridgeEngine()
        let playerVM = PlayerStateViewModel(
            videoURL: mediaURL,
            audioURL: nil,
            title: video.title,
            referer: "https://www.bilibili.com",
            engine: engine
        )
        let variant = PlayVariant(
            quality: 80,
            title: "1080P",
            videoURL: mediaURL,
            audioURL: nil,
            videoStream: nil,
            audioStream: nil,
            codec: "AVC",
            resolution: nil,
            frameRate: "24",
            bandwidth: 2_000_000,
            isHDR: false,
            badge: nil
        )
        detailVM.playVariants = [variant]
        detailVM.selectedPlayVariant = variant
        detailVM.state = .loaded
        detailVM.playURLState = .loaded
        detailVM.installStablePlayerViewModel(
            playerVM,
            variant: variant,
            resumeCandidate: PlaybackResumeCandidate(time: 0, sourceTitle: "test", reason: "test", cid: 101),
            resumeTime: 0,
            playbackRate: .x10,
            shouldAutoplay: true,
            playbackHandoffSource: nil
        )

        try await engine.prepare(source: PlayerStreamSource(
            metricsID: UUID().uuidString,
            videoURL: mediaURL,
            audioURL: nil,
            videoStream: nil,
            audioStream: nil,
            alternateVideoRenditions: [],
            referer: "https://www.bilibili.com",
            httpHeaders: [:],
            title: video.title,
            durationHint: 12,
            isLiveStream: false,
            isLiveHLS: false,
            liveHLSFormat: nil,
            resumeTime: 0,
            dynamicRange: .sdr,
            cdnPreference: .automatic
        ))
        playerVM.play()

        let runtime = VideoDetailRuntimeSettingsStore()
        runtime.bind(dependencies.libraryStore)
        let coordinator = PlaybackRotationCoordinator()
        let containerModel = VideoDetailSwiftUIContainerModel(
            viewModel: detailVM,
            initialVideo: video,
            runtimeSettings: runtime,
            rotationCoordinator: coordinator,
            initialContentTab: .detail
        )

        let root = VideoDetailSwiftUIContainer(
            viewModel: detailVM,
            model: containerModel,
            runtimeSettings: runtime,
            rotationCoordinator: coordinator,
            selectedContentTab: .constant(.detail),
            sheetRoute: .constant(nil),
            splitColumnOverlay: VideoDetailSplitColumnOverlayController(),
            submitReply: { _, _, _ in },
            dependencies: dependencies,
            onShowNetworkDiagnostics: {},
            onShowFavoriteFolders: {},
            onShowCoinPicker: {},
            onOpenCommentComposer: { _ in },
            onReply: { _ in },
            openVideoOwnerRoute: nil,
            onShowMoreControls: { _ in },
            onDismissMoreControls: {},
            onRequestFullscreen: { coordinator.setInPlaceFullscreen(true) },
            onExitFullscreen: { coordinator.setInPlaceFullscreen(false) },
            onToggleDanmaku: {},
            onShowDanmakuSettings: {},
            onNavigateBack: {}
        )

        let controller = UIHostingController(
            rootView: root
                .environmentObject(dependencies)
                .environmentObject(dependencies.libraryStore)
                .environmentObject(dependencies.sessionStore)
        )
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKey = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKey?.makeKey()
            playerVM.stop()
        }

        let initialSurfaceHost = try await waitForSurfaceHost(in: window)
        for _ in 0..<40 {
            if playerVM.isPlaying { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(playerVM.isPlaying)
        let initialSurfaceHostID = ObjectIdentifier(initialSurfaceHost)
        let initialPlayerVMID = ObjectIdentifier(playerVM)
        let initialAVPlayerID = try XCTUnwrap(playerVM.debugAVPlayerIdentity)
        let initialAVPlayerItemID = try XCTUnwrap(playerVM.debugAVPlayerItemIdentity)

        let sizes: [(CGSize, Bool)] = [
            (CGSize(width: 680, height: 800), false),   // Duo unfolded narrow portrait
            (CGSize(width: 780, height: 760), false),   // Duo unfolded wide split
            (CGSize(width: 1024, height: 1366), false), // iPad 13" portrait split
            (CGSize(width: 1366, height: 1024), false), // iPad 13" landscape split
            (CGSize(width: 1366, height: 1024), true),  // iPad in-place fullscreen
            (CGSize(width: 1366, height: 1024), false), // Exit fullscreen back to split
            (CGSize(width: 400, height: 1024), false),  // Narrow Slide Over / Duo cover
            (CGSize(width: 834, height: 1194), false),  // Re-expand to split
        ]

        for (index, entry) in sizes.enumerated() {
            if index == 2 {
                _ = engine.seek(toTime: 4)
            } else if index == 4 {
                playerVM.pause()
            } else if index == 6 {
                playerVM.play()
            }
            window.frame = CGRect(origin: .zero, size: entry.0)
            coordinator.setInPlaceFullscreen(entry.1)
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(80))

            let currentSurfaceHost = try XCTUnwrap(findSurfaceHost(in: window))
            XCTAssertEqual(ObjectIdentifier(currentSurfaceHost), initialSurfaceHostID, "Surface host recreated at step \(index) size=\(entry.0)")
            XCTAssertEqual(ObjectIdentifier(try XCTUnwrap(containerModel.surfacePlayerViewModel)), initialPlayerVMID)
            XCTAssertEqual(playerVM.debugAVPlayerIdentity, initialAVPlayerID, "AVPlayer recreated at step \(index)")
            XCTAssertEqual(playerVM.debugAVPlayerItemIdentity, initialAVPlayerItemID, "AVPlayerItem recreated at step \(index)")
            if index == 4 || index == 5 {
                XCTAssertFalse(playerVM.isPlaying, "Paused intent should stay paused across layout change at step \(index)")
            } else {
                if index == 6 {
                    for _ in 0..<20 {
                        if playerVM.isPlaying { break }
                        try await Task.sleep(for: .milliseconds(25))
                    }
                }
                XCTAssertTrue(playerVM.isPlaying, "Playing intent should remain active at step \(index)")
            }
        }
    }

    func testOrientationLockAllowsLandscapeOnRegularOrPadWindowAndLocksCompactPhone() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let compactWindow = UIWindow(windowScene: scene)
        compactWindow.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        compactWindow.traitOverrides.horizontalSizeClass = .compact
        compactWindow.traitOverrides.userInterfaceIdiom = .phone
        XCTAssertFalse(AdaptiveLayoutPolicy.allowsUnrestrictedRootOrientation(for: compactWindow))
        XCTAssertEqual(AppOrientationLock.resolvedSupportedOrientations(for: compactWindow), .portrait)

        let regularPhoneWindow = UIWindow(windowScene: scene)
        regularPhoneWindow.frame = CGRect(x: 0, y: 0, width: 780, height: 760)
        regularPhoneWindow.traitOverrides.horizontalSizeClass = .regular
        regularPhoneWindow.traitOverrides.userInterfaceIdiom = .phone
        XCTAssertTrue(AdaptiveLayoutPolicy.allowsUnrestrictedRootOrientation(for: regularPhoneWindow))
        XCTAssertEqual(AppOrientationLock.resolvedSupportedOrientations(for: regularPhoneWindow), .allButUpsideDown)

        let landscapeMaxPhoneWindow = UIWindow(windowScene: scene)
        landscapeMaxPhoneWindow.frame = CGRect(x: 0, y: 0, width: 956, height: 440)
        landscapeMaxPhoneWindow.traitOverrides.horizontalSizeClass = .regular
        landscapeMaxPhoneWindow.traitOverrides.verticalSizeClass = .compact
        landscapeMaxPhoneWindow.traitOverrides.userInterfaceIdiom = .phone
        XCTAssertFalse(AdaptiveLayoutPolicy.allowsUnrestrictedRootOrientation(for: landscapeMaxPhoneWindow))
        XCTAssertEqual(AppOrientationLock.resolvedSupportedOrientations(for: landscapeMaxPhoneWindow), .portrait)

        let padWindow = UIWindow(windowScene: scene)
        padWindow.frame = CGRect(x: 0, y: 0, width: 1024, height: 1366)
        padWindow.traitOverrides.horizontalSizeClass = .regular
        padWindow.traitOverrides.userInterfaceIdiom = .pad
        XCTAssertTrue(AdaptiveLayoutPolicy.allowsUnrestrictedRootOrientation(for: padWindow))
        XCTAssertEqual(AppOrientationLock.resolvedSupportedOrientations(for: padWindow), .all)
    }

    func testVerticalTrailingChromeRailDetectsDuoCoverPortraitOnly() {
        // iPhone Duo cover display (portrait)
        XCTAssertTrue(
            AdaptiveLayoutPolicy.usesVerticalTrailingChromeRail(
                containerSize: CGSize(width: 466, height: 678),
                safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 34, trailing: 84)
            )
        )
        // iPhone Duo unfolded inner display (landscape uses twoColumnSplit with right-column horizontal toolbar)
        XCTAssertFalse(
            AdaptiveLayoutPolicy.usesVerticalTrailingChromeRail(
                containerSize: CGSize(width: 951, height: 669),
                safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 20, trailing: 84)
            )
        )
        // Standard iPhone portrait
        XCTAssertFalse(
            AdaptiveLayoutPolicy.usesVerticalTrailingChromeRail(
                containerSize: CGSize(width: 440, height: 956),
                safeAreaInsets: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0)
            )
        )
        // iPhone Duo unfolded inner display (portrait)
        XCTAssertFalse(
            AdaptiveLayoutPolicy.usesVerticalTrailingChromeRail(
                containerSize: CGSize(width: 669, height: 951),
                safeAreaInsets: EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0)
            )
        )
        // Standard iPhone landscape (symmetric horizontal safe areas)
        XCTAssertFalse(
            AdaptiveLayoutPolicy.usesVerticalTrailingChromeRail(
                containerSize: CGSize(width: 956, height: 440),
                safeAreaInsets: EdgeInsets(top: 0, leading: 62, bottom: 21, trailing: 62)
            )
        )
        // iPad landscape
        XCTAssertFalse(
            AdaptiveLayoutPolicy.usesVerticalTrailingChromeRail(
                containerSize: CGSize(width: 1366, height: 1024),
                safeAreaInsets: EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0)
            )
        )
    }

    func testIsDuoUnfoldedInnerDisplayDetectsUnfoldedPhoneOnly() {
        XCTAssertTrue(
            AdaptiveLayoutPolicy.isDuoUnfoldedInnerDisplay(
                containerSize: CGSize(width: 669, height: 951),
                userInterfaceIdiom: .phone
            )
        )
        XCTAssertTrue(
            AdaptiveLayoutPolicy.isDuoUnfoldedInnerDisplay(
                containerSize: CGSize(width: 951, height: 669),
                userInterfaceIdiom: .phone
            )
        )
        XCTAssertFalse(
            AdaptiveLayoutPolicy.isDuoUnfoldedInnerDisplay(
                containerSize: CGSize(width: 466, height: 678),
                userInterfaceIdiom: .phone
            )
        )
        XCTAssertFalse(
            AdaptiveLayoutPolicy.isDuoUnfoldedInnerDisplay(
                containerSize: CGSize(width: 440, height: 956),
                userInterfaceIdiom: .phone
            )
        )
        XCTAssertFalse(
            AdaptiveLayoutPolicy.isDuoUnfoldedInnerDisplay(
                containerSize: CGSize(width: 956, height: 440),
                userInterfaceIdiom: .phone
            )
        )
        XCTAssertFalse(
            AdaptiveLayoutPolicy.isDuoUnfoldedInnerDisplay(
                containerSize: CGSize(width: 1024, height: 1366),
                userInterfaceIdiom: .pad
            )
        )
        XCTAssertFalse(
            AdaptiveLayoutPolicy.isDuoUnfoldedInnerDisplay(
                containerSize: CGSize(width: 1366, height: 1024),
                userInterfaceIdiom: .pad
            )
        )
    }

    func testReadableHorizontalContentMarginCapsLargeScreensWithoutShrinkingPhones() {
        // Standard iPhone (390pt) and Duo cover (466pt) keep their base inset unchanged.
        XCTAssertEqual(
            AdaptiveLayoutPolicy.readableHorizontalContentMargin(
                containerWidth: 390,
                baseInset: 20,
                maxContentWidth: AdaptiveLayoutPolicy.readableListMaxWidth,
                adaptiveEnabled: true
            ),
            20
        )
        XCTAssertEqual(
            AdaptiveLayoutPolicy.readableHorizontalContentMargin(
                containerWidth: 466,
                baseInset: 20,
                maxContentWidth: AdaptiveLayoutPolicy.readableListMaxWidth,
                adaptiveEnabled: true
            ),
            20
        )

        // Duo unfolded inner landscape (951pt) centers readable 760pt content: (951 - 760) / 2 = 95.5 -> 95.
        XCTAssertEqual(
            AdaptiveLayoutPolicy.readableHorizontalContentMargin(
                containerWidth: 951,
                baseInset: 20,
                maxContentWidth: AdaptiveLayoutPolicy.readableListMaxWidth,
                adaptiveEnabled: true
            ),
            95
        )

        // iPad 13" landscape (1366pt) centers 680pt form lists: (1366 - 680) / 2 = 343.
        XCTAssertEqual(
            AdaptiveLayoutPolicy.readableHorizontalContentMargin(
                containerWidth: 1366,
                baseInset: 20,
                maxContentWidth: AdaptiveLayoutPolicy.formListMaxWidth,
                adaptiveEnabled: true
            ),
            343
        )

        // Disabling adaptive large-screen layout falls back to base inset.
        XCTAssertEqual(
            AdaptiveLayoutPolicy.readableHorizontalContentMargin(
                containerWidth: 1366,
                baseInset: 20,
                maxContentWidth: AdaptiveLayoutPolicy.formListMaxWidth,
                adaptiveEnabled: false
            ),
            20
        )
    }

    func testDynamicWaterfallColumnCountAdaptsAcrossPhoneDuoAndIPadWidths() {
        XCTAssertEqual(AdaptiveLayoutPolicy.dynamicWaterfallColumnCount(containerWidth: 390), 2)
        XCTAssertEqual(AdaptiveLayoutPolicy.dynamicWaterfallColumnCount(containerWidth: 466), 2)
        XCTAssertEqual(AdaptiveLayoutPolicy.dynamicWaterfallColumnCount(containerWidth: 669), 3)
        XCTAssertEqual(AdaptiveLayoutPolicy.dynamicWaterfallColumnCount(containerWidth: 951), 4)
        XCTAssertEqual(AdaptiveLayoutPolicy.dynamicWaterfallColumnCount(containerWidth: 1024), 4)
        XCTAssertEqual(AdaptiveLayoutPolicy.dynamicWaterfallColumnCount(containerWidth: 1366), 5)
    }

    func testDynamicWaterfallLayoutPlannerPreservesColumnAssignmentsAcrossLoadMore() throws {
        func makeItem(id: String, width: Int? = nil, height: Int? = nil, text: String = "测试动态") throws -> DynamicFeedItem {
            let drawJSON: String
            if let width, let height {
                drawJSON = """
                "major":{"type":"MAJOR_TYPE_DRAW","draw":{"id":1,"items":[{"src":"https://i0.hdslb.com/bfs/new_dyn/\(id).jpg","width":\(width),"height":\(height)}]}}
                """
            } else {
                drawJSON = "\"major\":null"
            }
            let json = """
            {
              "id_str": "\(id)",
              "type": "DYNAMIC_TYPE_DRAW",
              "modules": {
                "module_author": {"mid": 1001, "name": "Tester", "face": "https://i0.hdslb.com/bfs/face/test.jpg", "pub_time": "1分钟前"},
                "module_dynamic": {
                  "desc": {"text": "\(text)", "rich_text_nodes": [{"type": "RICH_TEXT_NODE_TYPE_TEXT", "text": "\(text)"}]},
                  \(drawJSON)
                }
              }
            }
            """
            return try JSONDecoder.bili.decode(DynamicFeedItem.self, from: Data(json.utf8))
        }

        let planner = DynamicWaterfallLayoutPlanner()
        let firstBatch = [
            try makeItem(id: "dyn-1", width: 800, height: 1200, text: "长图"),
            try makeItem(id: "dyn-2", width: 1200, height: 800, text: "横图"),
            try makeItem(id: "dyn-3", width: 900, height: 900, text: "方图"),
            try makeItem(id: "dyn-4", text: "纯文字动态内容测试"),
        ]
        let initialColumns = planner.columns(for: firstBatch, columnCount: 2, cardWidth: 180)
        XCTAssertEqual(initialColumns.count, 2)
        XCTAssertEqual(initialColumns.flatMap { $0 }.count, 4)

        var initialColumnByID: [String: Int] = [:]
        for (colIdx, colItems) in initialColumns.enumerated() {
            for item in colItems {
                initialColumnByID[item.id] = colIdx
            }
        }

        // Appending next page must keep every previously placed item in its exact column.
        let secondBatch = firstBatch + [
            try makeItem(id: "dyn-5", width: 800, height: 1000, text: "第二页1"),
            try makeItem(id: "dyn-6", width: 1000, height: 800, text: "第二页2"),
        ]
        let expandedColumns = planner.columns(for: secondBatch, columnCount: 2, cardWidth: 180)
        XCTAssertEqual(expandedColumns.flatMap { $0 }.count, 6)
        for (colIdx, colItems) in expandedColumns.enumerated() {
            for item in colItems {
                if let previousCol = initialColumnByID[item.id] {
                    XCTAssertEqual(colIdx, previousCol, "Item \(item.id) shifted column on loadMore")
                }
            }
        }

        // Changing columnCount (e.g. rotating to 4 columns) rebalances cleanly across all columns.
        let fourColumns = planner.columns(for: secondBatch, columnCount: 4, cardWidth: 210)
        XCTAssertEqual(fourColumns.count, 4)
        XCTAssertEqual(fourColumns.flatMap { $0 }.count, 6)
        XCTAssertTrue(fourColumns.allSatisfy { !$0.isEmpty })
    }

    func testVideoDetailSplitColumnOverlayControllerManagesOwnershipAndDismissesOnExit() {
        let overlay = VideoDetailSplitColumnOverlayController()
        let ownerA = NSObject()
        let ownerB = NSObject()
        var dismissedCount = 0

        overlay.setSplitColumnMode(true)
        XCTAssertTrue(overlay.isSplitColumnMode)
        XCTAssertFalse(overlay.hasActiveOverlay)

        overlay.selectionSheet = VideoDetailSplitSelectionSheetPayload(
            sectionTitle: "分P",
            items: [],
            selectItem: { _ in }
        )
        XCTAssertTrue(overlay.hasActiveOverlay)
        overlay.presentInlineComposer(
            ownerID: ObjectIdentifier(ownerA),
            targetID: "root-1",
            content: AnyView(EmptyView()),
            onDismiss: { dismissedCount += 1 }
        )
        XCTAssertNotNil(overlay.selectionSheet)
        XCTAssertEqual(overlay.inlineComposer?.targetID, "root-1")

        // Unrelated owner must not dismiss ownerA's composer.
        overlay.dismissInlineComposerIfOwned(by: ObjectIdentifier(ownerB))
        XCTAssertNotNil(overlay.inlineComposer)

        // Exiting split column mode clears all split overlays and invokes composer onDismiss.
        overlay.setSplitColumnMode(false)
        XCTAssertFalse(overlay.isSplitColumnMode)
        XCTAssertFalse(overlay.hasActiveOverlay)
        XCTAssertNil(overlay.selectionSheet)
        XCTAssertNil(overlay.commentDialogSheet)
        XCTAssertNil(overlay.inlineComposer)
        XCTAssertEqual(dismissedCount, 1)
    }

    func testHomeFeedLayoutTitlesReflectAdaptiveNaming() {
        XCTAssertEqual(HomeFeedLayout.doubleColumn.title, "自适应布局")
        XCTAssertEqual(HomeFeedLayout.borderedDoubleColumn.title, "有边框自适应布局")
        XCTAssertEqual(HomeFeedLayout.singleColumn.title, "单列")
        XCTAssertEqual(HomeFeedLayout.borderedSingleColumn.title, "有边框单列")
    }

    func testDynamicFeedLayoutModeDefaultsToListAndPersistsToggle() {
        let store = LibraryStore()
        let previous = store.dynamicFeedLayoutMode
        defer { store.setDynamicFeedLayoutMode(previous) }

        store.setDynamicFeedLayoutMode(.list)
        XCTAssertEqual(LibraryStore().dynamicFeedLayoutMode, .list)

        store.setDynamicFeedLayoutMode(.waterfall)
        XCTAssertEqual(store.dynamicFeedLayoutMode, .waterfall)
        XCTAssertEqual(LibraryStore().dynamicFeedLayoutMode, .waterfall)
    }

    private func waitForSurfaceHost(in root: UIView) async throws -> DirectUIKitPlayerSurfaceHostView {
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            if let found = findSurfaceHost(in: root) {
                return found
            }
            try await Task.sleep(for: .milliseconds(30))
        }
        return try XCTUnwrap(findSurfaceHost(in: root))
    }

    private func findSurfaceHost(in view: UIView) -> DirectUIKitPlayerSurfaceHostView? {
        if let host = view as? DirectUIKitPlayerSurfaceHostView {
            return host
        }
        for subview in view.subviews {
            if let found = findSurfaceHost(in: subview) {
                return found
            }
        }
        return nil
    }

    func testCancelledCommentReplyLoadResetsToIdleAndAutoLoadsOnRetry() async throws {
        final class ReplyProbeURLProtocol: URLProtocol, @unchecked Sendable {
            nonisolated(unsafe) static var requestCount = 0

            override class func canInit(with request: URLRequest) -> Bool { true }
            override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

            override func startLoading() {
                Self.requestCount += 1
                let attempt = Self.requestCount
                guard let url = request.url else {
                    client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                    return
                }
                if attempt == 1 {
                    client?.urlProtocol(self, didFailWithError: CancellationError())
                    return
                }
                let payload = """
                {
                  "code": 0,
                  "message": "0",
                  "data": {
                    "page": {"num": 1, "size": 20, "count": 1},
                    "replies": [
                      {
                        "rpid": 2002,
                        "oid": 12345,
                        "type": 1,
                        "mid": 88,
                        "root": 1001,
                        "parent": 1001,
                        "rcount": 0,
                        "like": 3,
                        "ctime": 1700000000,
                        "member": {"mid": "88", "uname": "测试回复者"},
                        "content": {"message": "自动加载成功"}
                      }
                    ]
                  }
                }
                """
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data(payload.utf8))
                client?.urlProtocolDidFinishLoading(self)
            }

            override func stopLoading() {}
        }

        ReplyProbeURLProtocol.requestCount = 0
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ReplyProbeURLProtocol.self]
        let session = URLSession(configuration: config)
        let dependencies = AppDependencies()
        let api = BiliAPIClient(
            session: session,
            sessionStore: dependencies.sessionStore,
            libraryStore: dependencies.libraryStore,
            homeRecommendDiagnosticsStore: .shared
        )

        let video = try JSONDecoder.bili.decode(VideoItem.self, from: Data("""
            {"bvid":"BVReplyCancelProbe","aid":12345,"title":"Reply probe"}
            """.utf8))
        let rootComment = try JSONDecoder.bili.decode(Comment.self, from: Data("""
            {
              "rpid": 1001,
              "oid": 12345,
              "type": 1,
              "mid": 77,
              "root": 0,
              "parent": 0,
              "rcount": 1,
              "like": 10,
              "ctime": 1700000000,
              "member": {"mid": "77", "uname": "主评论"},
              "content": {"message": "这是一条主评论"}
            }
            """.utf8))

        let viewModel = VideoDetailViewModel(
            seedVideo: video,
            api: api,
            libraryStore: dependencies.libraryStore,
            sessionStore: dependencies.sessionStore,
            sponsorBlockService: dependencies.sponsorBlockService
        )

        // First attempt gets cancelled (simulating SwiftUI .task cancellation during sheet transition).
        await viewModel.loadReplies(for: rootComment)
        XCTAssertEqual(viewModel.replyState(for: rootComment), .idle)
        XCTAssertNil(viewModel.replyThreads[rootComment.id])

        // Second automatic loadReplies call (e.g. re-appearing sheet .task) must NOT be skipped.
        await viewModel.loadReplies(for: rootComment)
        XCTAssertEqual(viewModel.replyState(for: rootComment), .loaded)
        XCTAssertEqual(viewModel.replies(for: rootComment).map(\.rpid), [2002])
    }

    func testVideoDetailSheetHeightPolicyStaysBelowVideoAcrossAspectRatiosAndPreservesDynamicFallback() {
        // iPhone 18 Pro Max portrait (440x956, top 62, bottom 34), 16:9 video (playerHeight=248 -> bottom=310)
        let phone16x9 = VideoDetailSheetHeightPolicy.belowVideoDetentHeight(
            containerHeight: 956,
            playerBottomY: 310,
            bottomSafeAreaInset: 34
        )
        XCTAssertEqual(phone16x9, 612)

        // 4:3 video on same phone (playerHeight=330 -> bottom=392): shorter than 70% so it never covers video
        let phone4x3 = VideoDetailSheetHeightPolicy.belowVideoDetentHeight(
            containerHeight: 956,
            playerBottomY: 392,
            bottomSafeAreaInset: 34
        )
        XCTAssertEqual(phone4x3, 530)
        XCTAssertLessThan(phone4x3 ?? .greatestFiniteMagnitude, 956 * 0.7)

        // Vertical 9:16 video (playerHeight=621 -> bottom=683): strictly below video
        let phoneVertical = VideoDetailSheetHeightPolicy.belowVideoDetentHeight(
            containerHeight: 956,
            playerBottomY: 683,
            bottomSafeAreaInset: 34
        )
        XCTAssertEqual(phoneVertical, 239)

        // Dynamic page (videoDetailMaxHeight == nil) keeps its 70% limit
        XCTAssertEqual(
            CommentSheetPresentationPolicy.detents(
                limitsMaxHeight: true,
                verticalSizeClass: .regular,
                videoDetailMaxHeight: nil
            ),
            [.fraction(CommentInteractionSettings.limitedSheetDetentFraction)]
        )

        // Video detail page uses the computed below-video height instead of 70%
        XCTAssertEqual(
            CommentSheetPresentationPolicy.detents(
                limitsMaxHeight: true,
                verticalSizeClass: .regular,
                videoDetailMaxHeight: phone4x3
            ),
            [.height(530)]
        )

        // Disabling height limit restores [.medium, .large]
        XCTAssertEqual(
            CommentSheetPresentationPolicy.detents(
                limitsMaxHeight: false,
                verticalSizeClass: .regular,
                videoDetailMaxHeight: phone4x3
            ),
            [.medium, .large]
        )
    }

    func testDuoFoldedContentHorizontalBoundsConstrainsDisplayToLeft16By9Strip() {
        // iPhone Duo folded cover display (466x678pt) with ~84pt trailing vertical chrome rail:
        // left 9:16 portrait strip = floor(678 * 9 / 16) = 381pt.
        let duoFoldedBounds = CGRect(x: 0, y: 0, width: 466, height: 678)
        let duoFoldedInsets = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 84)
        let resolved = AdaptiveLayoutPolicy.duoFoldedContentHorizontalBounds(
            containerBounds: duoFoldedBounds,
            safeAreaInsets: duoFoldedInsets
        )
        XCTAssertEqual(resolved?.minX, 0)
        XCTAssertEqual(resolved?.width, 381)

        // If trailing rail is wider than 466 - 381 (e.g. 92pt), clamp to safeWidth (374pt)
        // so elements still never overlap the trailing controls.
        let widerRail = AdaptiveLayoutPolicy.duoFoldedContentHorizontalBounds(
            containerBounds: duoFoldedBounds,
            safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 92)
        )
        XCTAssertEqual(widerRail?.width, 374)

        // VideoDetailShellLayout constrains player + content to the left 381pt strip while
        // keeping full-width container bounds for the extended background.
        let detailLayout = VideoDetailShellLayout.resolve(
            bounds: duoFoldedBounds,
            safeAreaTop: 0,
            safeAreaBottom: 0,
            safeAreaLeading: 0,
            safeAreaTrailing: 84,
            videoAspectRatio: 16.0 / 9.0,
            currentPlayerHeight: nil,
            isPlaybackActive: true,
            isLandscape: false,
            isPortraitFullscreen: false,
            horizontalSizeClass: .compact,
            adaptiveLargeScreenEnabled: true
        )
        XCTAssertEqual(detailLayout.adaptiveMode, .compactStacked)
        XCTAssertTrue(detailLayout.usesDuoFoldedHorizontalBounds)
        XCTAssertEqual(detailLayout.playerFrame.minX, 0)
        XCTAssertEqual(detailLayout.playerFrame.width, 381)
        XCTAssertEqual(detailLayout.playerFrame.height, 214) // round(381 * 9 / 16)
        XCTAssertEqual(detailLayout.contentFrame.minX, 0)
        XCTAssertEqual(detailLayout.contentFrame.width, 381)
        XCTAssertEqual(detailLayout.contentFrame.height, 678)

        // Fullscreen playback on Duo cover still fills full bounds.
        let fullscreenLayout = VideoDetailShellLayout.resolve(
            bounds: duoFoldedBounds,
            safeAreaTop: 0,
            safeAreaBottom: 0,
            safeAreaLeading: 0,
            safeAreaTrailing: 84,
            videoAspectRatio: 16.0 / 9.0,
            currentPlayerHeight: nil,
            isPlaybackActive: true,
            isLandscape: false,
            isPortraitFullscreen: true,
            horizontalSizeClass: .compact,
            adaptiveLargeScreenEnabled: true
        )
        XCTAssertFalse(fullscreenLayout.usesDuoFoldedHorizontalBounds)
        XCTAssertEqual(fullscreenLayout.playerFrame.width, 466)

        // Standard iPhone portrait (393x852pt, no trailing chrome rail) is unaffected.
        XCTAssertNil(
            AdaptiveLayoutPolicy.duoFoldedContentHorizontalBounds(
                containerBounds: CGRect(x: 0, y: 0, width: 393, height: 852),
                safeAreaInsets: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
            )
        )

        // ScrollView GeometryProxy on Duo folded cover may report full 466pt width
        // (with or without horizontal safeAreaInsets); safeContentWidth must resolve
        // to the 381pt left 9:16 strip without double-subtracting.
        XCTAssertEqual(
            AdaptiveLayoutPolicy.safeContentWidth(
                containerSize: duoFoldedBounds.size,
                safeAreaInsets: duoFoldedInsets
            ),
            381
        )
        XCTAssertEqual(
            AdaptiveLayoutPolicy.safeContentWidth(
                containerSize: duoFoldedBounds.size,
                safeAreaInsets: EdgeInsets(),
                windowBoundsSize: duoFoldedBounds.size,
                windowSafeAreaInsets: duoFoldedInsets
            ),
            381
        )
        XCTAssertEqual(
            AdaptiveLayoutPolicy.safeContentWidth(
                containerSize: CGSize(width: 382, height: 678),
                safeAreaInsets: EdgeInsets(),
                windowBoundsSize: duoFoldedBounds.size,
                windowSafeAreaInsets: duoFoldedInsets
            ),
            381
        )

        // Form/List horizontal contentMargins must reserve 85pt trailing clearance on
        // folded Duo (466 - 381) so grouped sections never enter the right chrome rail,
        // while staying 0 on standard iPhone.
        XCTAssertEqual(
            AdaptiveLayoutPolicy.duoFoldedTrailingChromeClearance(
                containerSize: duoFoldedBounds.size,
                safeAreaInsets: duoFoldedInsets
            ),
            85
        )
        XCTAssertEqual(
            AdaptiveLayoutPolicy.duoFoldedTrailingChromeClearance(
                containerSize: CGSize(width: 393, height: 852),
                safeAreaInsets: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
            ),
            0
        )
    }

    private func makeLocalTestVideo() async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("adaptive-layout-probe-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 320,
            AVVideoHeightKey: 180,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: 320,
                kCVPixelBufferHeightKey as String: 180,
            ]
        )
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        for index in 0...20 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            var buffer: CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferPoolCreatePixelBuffer(nil, try XCTUnwrap(adaptor.pixelBufferPool), &buffer), kCVReturnSuccess)
            let pixelBuffer = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            XCTAssertTrue(adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: Int64(index), timescale: 1)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        return url
    }
}
