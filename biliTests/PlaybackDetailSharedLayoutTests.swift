import Combine
import SwiftUI
import UIKit
import XCTest
@testable import bili

final class PlaybackDetailSharedLayoutTests: XCTestCase {
    @MainActor
    func testFullWidthAspectRatioUsesAspectHeightAndStableSixteenNineFloor() {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 844)
        let minimum = VideoDetailShellLayout.standardPlayerHeight(forWidth: bounds.width)
        // Height must not exceed width; only pictures taller than 16:9 apply.
        for ratio: CGFloat in [1, 4.0 / 3, 3.0 / 2, 1.77] {
            let expanded = bounds.width / ratio
            for playing in [false, true] {
                XCTAssertTrue(VideoDetailShellLayout.supportsInteractiveCollapse(
                    videoAspectRatio: ratio, isPlaybackActive: playing))
                for requested in [nil, expanded - 100, minimum, CGFloat(0)] as [CGFloat?] {
                    let layout = VideoDetailShellLayout.resolve(bounds: bounds, safeAreaTop: 59,
                        videoAspectRatio: ratio, currentPlayerHeight: requested, isPlaybackActive: playing,
                        isLandscape: false, isPortraitFullscreen: false)
                    XCTAssertEqual(layout.playerFrame.width, bounds.width)
                    XCTAssertEqual(layout.playerFrame.height, max(minimum, requested ?? expanded), accuracy: 0.001)
                    XCTAssertEqual(layout.playerFrame.minY, 59)
                    XCTAssertEqual(layout.contentTopInset, expanded)
                    XCTAssertEqual(layout.danmakuCanvasSize, CGSize(width: bounds.width, height: expanded))
                }
                let scrollHeight = VideoDetailShellLayout.scrollContentMinimumHeight(
                    viewportHeight: 785, expandedPlayerHeight: expanded, minimumPlayerHeight: minimum)
                XCTAssertEqual(scrollHeight - 785, expanded - minimum, accuracy: 0.001)
            }
        }
    }

    @MainActor
    func testFullWidthAspectRatioLeavesVerticalWidescreenAndFullscreenUnchanged() {
        let portraitBounds = CGRect(x: 0, y: 0, width: 390, height: 844)
        let standard = VideoDetailShellLayout.standardPlayerHeight(forWidth: 390)
        for ratio: CGFloat in [0.05, 9.0 / 16, 3.0 / 4, 0.99, 16.0 / 9, 2, 21.0 / 9] {
            let expanded = ratio < 0.9 ? max(standard, min(max(844 * 0.65, 390), max(standard, 844 * 0.72))) : standard
            for playing in [true, false] {
                let layout = VideoDetailShellLayout.resolve(bounds: portraitBounds, safeAreaTop: 59,
                    videoAspectRatio: ratio, currentPlayerHeight: 54, isPlaybackActive: playing,
                    isLandscape: false, isPortraitFullscreen: false)
                XCTAssertEqual(layout.playerFrame.height, playing ? standard : 54)
                XCTAssertEqual(layout.danmakuCanvasSize.height, expanded)
                XCTAssertEqual(layout.contentTopInset, !playing || ratio < 0.9 ? expanded : standard)
            }
        }
        for ratio: CGFloat in [1, 4.0 / 3, 3.0 / 2, 9.0 / 16, 16.0 / 9, 2] {
            for landscape in [false, true] {
                let bounds = landscape ? CGRect(x: 0, y: 0, width: 844, height: 390) : portraitBounds
                let layout = VideoDetailShellLayout.resolve(bounds: bounds, safeAreaTop: 59,
                    videoAspectRatio: ratio, currentPlayerHeight: 100, isPlaybackActive: true,
                    isLandscape: landscape, isPortraitFullscreen: !landscape)
                XCTAssertEqual(layout.playerFrame, bounds)
                XCTAssertEqual(layout.danmakuCanvasSize, bounds.size)
                XCTAssertNil(layout.contentTopInset)
            }
        }
        for ratio: CGFloat in [0, -1, 0.99, 16.0 / 9, 2, .infinity, .nan] {
            XCTAssertFalse(VideoDetailShellLayout.usesFullWidthAspectRatioVideo(videoAspectRatio: ratio))
        }
    }

    @MainActor
    func testFullWidthAspectRatioModelScrollsCollapsesAndPreservesContentTabPositions() throws {
        let dependencies = AppDependencies()
        let model = try makeAspectRatioContainerModel(dependencies: dependencies, width: 1200, height: 900)
        let size = CGSize(width: 390, height: 844)
        let coordinator = model.rotationCoordinator
        let expanded = size.width * 3 / 4
        let minimum = VideoDetailShellLayout.standardPlayerHeight(forWidth: size.width)
        let distance = expanded - minimum
        XCTAssertTrue(model.isInteractiveScrollCollapseActive)
        XCTAssertEqual(model.layout(in: size, safeAreaTop: 59, rotationCoordinator: coordinator).playerFrame.height, expanded, accuracy: 0.001)
        model.recordInteractiveScrollOffset(tab: .detail, offset: 20, selectedTab: .detail, bounds: size)
        XCTAssertEqual(model.layout(in: size, safeAreaTop: 59, rotationCoordinator: coordinator).playerFrame.height, expanded - 20, accuracy: 0.001)
        model.recordInteractiveScrollOffset(tab: .detail, offset: distance + 120, selectedTab: .detail, bounds: size)
        XCTAssertEqual(model.layout(in: size, safeAreaTop: 59, rotationCoordinator: coordinator).playerFrame.height, minimum)
        XCTAssertFalse(model.isCollapsedChromeActive)
        XCTAssertEqual(model.interactiveScrollContentMinimumPlayerHeight(forWidth: size.width), minimum)
        XCTAssertEqual(model.prepareInteractiveTabChange(to: .comments, bounds: size), distance, accuracy: 0.001)
        model.recordInteractiveScrollOffset(tab: .comments, offset: distance, selectedTab: .comments, bounds: size)
        XCTAssertEqual(model.prepareInteractiveTabChange(to: .detail, bounds: size), distance + 120, accuracy: 0.001)
        model.recordInteractiveScrollOffset(tab: .detail, offset: distance + 120, selectedTab: .detail, bounds: size)
        model.recordInteractiveScrollOffset(tab: .detail, offset: 0, selectedTab: .detail, bounds: size)
        XCTAssertEqual(model.layout(in: size, safeAreaTop: 59, rotationCoordinator: coordinator).playerFrame.height, expanded, accuracy: 0.001)
    }

    @MainActor
    func testFullWidthAspectRatioIsProductionBehaviorRegardlessOfRetiredSettings() throws {
        let dependencies = AppDependencies()
        // Previously saved OFF values must no longer disable production behavior.
        let key = "cc.bili.videoDetail.fullWidthPortraitExperimentEnabled.v1"
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: key)
        defer {
            if let previous { defaults.set(previous, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        defaults.set(false, forKey: key)
        let model = try makeAspectRatioContainerModel(dependencies: dependencies, width: 1200, height: 800)
        let size = CGSize(width: 390, height: 844)
        XCTAssertEqual(model.layout(in: size, safeAreaTop: 59, rotationCoordinator: model.rotationCoordinator).playerFrame.height,
                       size.width * 2 / 3, accuracy: 0.001)
        model.recordInteractiveScrollOffset(tab: .detail, offset: 1000, selectedTab: .detail, bounds: size)
        XCTAssertEqual(model.layout(in: size, safeAreaTop: 59, rotationCoordinator: model.rotationCoordinator).playerFrame.height,
                       VideoDetailShellLayout.standardPlayerHeight(forWidth: size.width))
        let narrow = try makeAspectRatioContainerModel(dependencies: dependencies, width: 100, height: 2000)
        XCTAssertEqual(narrow.videoAspectRatio, VideoDetailInitialVideoGeometry.defaultAspectRatio)
        XCTAssertEqual(narrow.layout(in: size, safeAreaTop: 59, rotationCoordinator: narrow.rotationCoordinator).playerFrame.height,
                       VideoDetailShellLayout.standardPlayerHeight(forWidth: size.width), accuracy: 0.001)
    }

    @MainActor
    private func makeAspectRatioContainerModel(dependencies: AppDependencies, width: Int, height: Int) throws -> VideoDetailSwiftUIContainerModel {
        let video = try JSONDecoder.bili.decode(VideoItem.self, from: Data("""
            {"bvid":"BVAspectRatioLayoutProbe","title":"Aspect ratio layout probe","cid":1,"dimension":{"width":\(width),"height":\(height),"rotate":0}}
            """.utf8))
        let detail = VideoDetailViewModel(seedVideo: video, api: dependencies.api,
            libraryStore: dependencies.libraryStore, sessionStore: dependencies.sessionStore,
            sponsorBlockService: dependencies.sponsorBlockService)
        let runtime = VideoDetailRuntimeSettingsStore()
        runtime.bind(dependencies.libraryStore)
        return VideoDetailSwiftUIContainerModel(viewModel: detail, initialVideo: video,
            runtimeSettings: runtime, rotationCoordinator: PlaybackRotationCoordinator(), initialContentTab: .detail)
    }

    @MainActor
    func testFullWidthAspectRatioContainerCollapsesThroughItsActualScrollHost() async throws {
        let dependencies = AppDependencies()
        for (sourceWidth, sourceHeight) in [(1000, 1000), (1200, 900), (1200, 800)] {
            let model = try makeAspectRatioContainerModel(dependencies: dependencies, width: sourceWidth, height: sourceHeight)
            let root = VideoDetailSwiftUIContainer(
                viewModel: model.viewModel, model: model, runtimeSettings: model.runtimeSettings,
                rotationCoordinator: model.rotationCoordinator, selectedContentTab: .constant(.detail),
                dependencies: dependencies, onShowNetworkDiagnostics: {}, onShowFavoriteFolders: {},
                onShowCoinPicker: {}, onOpenCommentComposer: { _ in }, onReply: { _ in },
                openVideoOwnerRoute: nil, onShowMoreControls: { _ in }, onDismissMoreControls: {},
                onRequestFullscreen: {}, onExitFullscreen: {}, onToggleDanmaku: {},
                onShowDanmakuSettings: {}, onNavigateBack: {})
            let controller = UIHostingController(rootView: root
                .environmentObject(dependencies)
                .environmentObject(dependencies.libraryStore)
                .environmentObject(dependencies.sessionStore))
            let window = try makeWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            let previousWindow = window.windowScene?.windows.first { $0.isKeyWindow }
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            defer { window.isHidden = true; window.rootViewController = nil; previousWindow?.makeKey() }
            try await waitUntil("initial layout for \(sourceWidth)x\(sourceHeight)") {
                model.playerFrame.width > 0 && model.contentState.topInset > 0
            }
            let width = model.playerFrame.width
            let expanded = width * CGFloat(sourceHeight) / CGFloat(sourceWidth)
            let minimum = VideoDetailShellLayout.standardPlayerHeight(forWidth: width)
            XCTAssertEqual(model.playerFrame.height, expanded, accuracy: 0.001)
            controller.view.layoutIfNeeded()
            let scrollView = try XCTUnwrap(detailScrollViews(in: controller.view).first)
            XCTAssertGreaterThanOrEqual(scrollView.contentSize.height + scrollView.contentInset.bottom - scrollView.bounds.height,
                                        expanded - minimum)
            // The production host deliberately ignores offsets until a user drag
            // begins. Drive that public delegate lifecycle instead of bypassing it.
            scrollView.delegate?.scrollViewWillBeginDragging?(scrollView)
            scrollView.setContentOffset(CGPoint(x: 0, y: expanded - minimum + 50), animated: false)
            scrollView.delegate?.scrollViewDidEndDragging?(scrollView, willDecelerate: false)
            try await waitUntil("collapse for \(sourceWidth)x\(sourceHeight)") {
                abs(model.playerFrame.height - minimum) < 0.5
            }
            XCTAssertEqual(model.playerFrame.height, minimum)
            XCTAssertEqual(model.contentState.topInset, expanded, accuracy: 0.001)
            XCTAssertFalse(model.isCollapsedChromeActive)
            scrollView.setContentOffset(.zero, animated: false)
            try await waitUntil("expansion for \(sourceWidth)x\(sourceHeight)") {
                abs(model.playerFrame.height - expanded) < 0.5
            }
            XCTAssertEqual(model.playerFrame.height, expanded, accuracy: 0.001)
        }
    }

    @MainActor
    private func detailScrollViews(in view: UIView) -> [UIScrollView] {
        let own = (view as? UIScrollView).map { [$0] } ?? []
        return own + view.subviews.flatMap { detailScrollViews(in: $0) }
    }

    @MainActor
    func testDanmakuCanvasStaysExpandedAcrossCollapseAndPauseButChangesForFullscreen() {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 844)
        let aspect: CGFloat = 9.0 / 16
        let expanded = VideoDetailShellLayout.expandedPlayerHeight(bounds: bounds.size, videoAspectRatio: aspect)
        for playing in [true, false] {
            for height in [expanded, 350, 220, 54] {
                let layout = VideoDetailShellLayout.resolve(bounds: bounds, safeAreaTop: 59,
                    videoAspectRatio: aspect, currentPlayerHeight: height, isPlaybackActive: playing,
                    isLandscape: false, isPortraitFullscreen: false)
                XCTAssertEqual(layout.danmakuCanvasSize, CGSize(width: 390, height: expanded))
                XCTAssertLessThanOrEqual(layout.playerFrame.height, expanded)
            }
        }
        for landscape in [false, true] {
            let fullscreenBounds = landscape ? CGRect(x: 0, y: 0, width: 844, height: 390) : bounds
            let layout = VideoDetailShellLayout.resolve(bounds: fullscreenBounds, safeAreaTop: 0,
                videoAspectRatio: aspect, currentPlayerHeight: 220, isPlaybackActive: true,
                isLandscape: landscape, isPortraitFullscreen: !landscape)
            XCTAssertEqual(layout.danmakuCanvasSize, fullscreenBounds.size)
        }
        let wide = VideoDetailShellLayout.resolve(bounds: bounds, safeAreaTop: 59,
            videoAspectRatio: 16.0 / 9, currentPlayerHeight: 54, isPlaybackActive: false,
            isLandscape: false, isPortraitFullscreen: false)
        XCTAssertEqual(wide.danmakuCanvasSize.height, VideoDetailShellLayout.standardPlayerHeight(forWidth: 390))
    }

    @MainActor
    func testContentUpdateGateCoalescesDeferredChangesIntoOneRefresh() async {
        let gate = VideoDetailContentUpdateGate()

        gate.receiveUpdate()
        gate.setUpdatesDeferred(true)
        gate.receiveUpdate()
        gate.receiveUpdate()

        XCTAssertEqual(gate.revision, 0)

        gate.setUpdatesDeferred(false)

        XCTAssertEqual(gate.revision, 1)
        gate.setUpdatesDeferred(false)
        XCTAssertEqual(gate.revision, 1)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
        XCTAssertEqual(gate.revision, 1)
    }

    @MainActor
    func testContentRenderStorePublishesOnlyLatestDeferredSnapshot() {
        let store = VideoDetailInteractionRenderStore()
        var publicationCount = 0
        let cancellable = store.objectWillChange.sink {
            publicationCount += 1
        }

        store.setUpdatesDeferred(true)
        store.update(
            interactionState: VideoInteractionState(),
            interactionMessage: "first",
            isMutatingInteraction: false,
            isMutatingLike: false,
            isMutatingCoin: false,
            isMutatingFavorite: false,
            isMutatingFollow: false,
            playbackFallbackMessage: nil
        )
        store.update(
            interactionState: VideoInteractionState(),
            interactionMessage: "latest",
            isMutatingInteraction: false,
            isMutatingLike: false,
            isMutatingCoin: false,
            isMutatingFavorite: false,
            isMutatingFollow: false,
            playbackFallbackMessage: nil
        )

        XCTAssertNil(store.interactionMessage)
        XCTAssertEqual(publicationCount, 0)

        store.setUpdatesDeferred(false)

        XCTAssertEqual(store.interactionMessage, "latest")
        XCTAssertEqual(publicationCount, 1)
        withExtendedLifetime(cancellable) {}
    }

    @MainActor
    func testPlaybackRenderStorePublishesOnlyLatestDeferredSnapshot() {
        let store = VideoDetailPlaybackRenderStore()
        var publicationCount = 0
        let cancellable = store.objectWillChange.sink {
            publicationCount += 1
        }

        store.setUpdatesDeferred(true)
        store.update(VideoDetailPlaybackRenderSnapshot(historyCID: 1))
        store.update(VideoDetailPlaybackRenderSnapshot(historyCID: 2))

        XCTAssertNil(store.historyCID)
        XCTAssertEqual(publicationCount, 0)

        store.setUpdatesDeferred(false)

        XCTAssertEqual(store.historyCID, 2)
        XCTAssertEqual(publicationCount, 1)
        withExtendedLifetime(cancellable) {}
    }

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
        XCTAssertEqual(PlaybackDetailContentMetrics.contentWidth(for: 393), 353)
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

    @MainActor
    func testVideoDetailShellLayoutReservesExpandedContentInsetDuringCollapse() {
        let layout = VideoDetailShellLayout.resolve(
            bounds: CGRect(x: 0, y: 0, width: 393, height: 852),
            safeAreaTop: 59,
            videoAspectRatio: 16.0 / 9.0,
            currentPlayerHeight: 54,
            isPlaybackActive: false,
            isLandscape: false,
            isPortraitFullscreen: false
        )

        XCTAssertEqual(layout.playerFrame.height, 54)
        XCTAssertEqual(
            layout.contentTopInset,
            VideoDetailShellLayout.expandedPlayerHeight(
                bounds: CGSize(width: 393, height: 852),
                videoAspectRatio: 16.0 / 9.0
            )
        )
        XCTAssertEqual(layout.contentFrame, CGRect(x: 0, y: 59, width: 393, height: 793))
    }

    @MainActor
    func testVideoLayoutReservesPortraitTopAndFillsLandscapeRoot() {
        for size in [CGSize(width: 420, height: 912), CGSize(width: 1368, height: 630)] {
            let bounds = CGRect(origin: .zero, size: size)
            let landscape = size.width > size.height
            let layout = VideoDetailShellLayout.resolve(
                bounds: bounds, safeAreaTop: 62, videoAspectRatio: 4.0 / 3.0,
                currentPlayerHeight: nil, isPlaybackActive: true,
                isLandscape: landscape, isPortraitFullscreen: false
            )
            if landscape {
                XCTAssertEqual(layout.playerFrame, bounds)
                XCTAssertNil(layout.contentTopInset)
            } else {
                XCTAssertEqual(layout.playerFrame.minY, 62)
                XCTAssertEqual(layout.contentFrame.minY, 62)
                XCTAssertEqual(layout.contentTopInset, layout.playerFrame.height)
            }
        }
    }

    @MainActor
    func testVideoDetailInitialVideoGeometryUsesPageDimensionWhenTopLevelDimensionIsMissing() {
        let pageDimension = VideoDimension(width: 1080, height: 1920, rotate: nil)
        let video = VideoItem(
            bvid: "BV1initial",
            aid: nil,
            title: "竖屏视频",
            pic: nil,
            desc: nil,
            duration: nil,
            pubdate: nil,
            owner: nil,
            stat: nil,
            cid: 1,
            pages: [
                VideoPage(
                    cid: 1,
                    page: 1,
                    part: "P1",
                    duration: 1,
                    dimension: pageDimension
                )
            ],
            dimension: nil,
            historyResumeTime: nil,
            historyCID: nil
        )

        XCTAssertEqual(
            VideoDetailInitialVideoGeometry.metadataAspectRatio(for: video),
            9.0 / 16.0
        )
    }

    @MainActor
    func testVideoDetailInteractiveCollapseKeepsPlayingVerticalVideoAtStandardHeight() {
        let layout = VideoDetailShellLayout.resolve(
            bounds: CGRect(x: 0, y: 0, width: 420, height: 912),
            safeAreaTop: 62,
            videoAspectRatio: 9.0 / 16.0,
            currentPlayerHeight: 0,
            isPlaybackActive: true,
            isLandscape: false,
            isPortraitFullscreen: false
        )

        XCTAssertEqual(
            layout.playerFrame.height,
            VideoDetailShellLayout.standardPlayerHeight(forWidth: 420)
        )
        XCTAssertEqual(
            layout.contentTopInset,
            VideoDetailShellLayout.expandedPlayerHeight(
                bounds: CGSize(width: 420, height: 912),
                videoAspectRatio: 9.0 / 16.0
            )
        )
    }

    @MainActor
    func testVideoDetailInteractiveCollapseAllowsVerticalVideosToReachToolbarHeight() {
        let layout = VideoDetailShellLayout.resolve(
            bounds: CGRect(x: 0, y: 0, width: 420, height: 912),
            safeAreaTop: 62,
            videoAspectRatio: 9.0 / 16.0,
            currentPlayerHeight: 0,
            isPlaybackActive: false,
            isLandscape: false,
            isPortraitFullscreen: false
        )

        XCTAssertEqual(layout.playerFrame.height, VideoDetailShellLayout.collapsedToolbarHeight)
    }

    @MainActor
    func testInteractiveScrollContentUsesPlayerCollapseDistance() {
        XCTAssertEqual(
            VideoDetailShellLayout.scrollContentMinimumHeight(
                viewportHeight: 812,
                expandedPlayerHeight: 420,
                minimumPlayerHeight: VideoDetailShellLayout.collapsedToolbarHeight
            ),
            1178
        )
        XCTAssertEqual(
            VideoDetailShellLayout.scrollContentMinimumHeight(
                viewportHeight: 812,
                expandedPlayerHeight: 40,
                minimumPlayerHeight: VideoDetailShellLayout.collapsedToolbarHeight
            ),
            812
        )
        XCTAssertEqual(
            VideoDetailShellLayout.scrollContentMinimumHeight(
                viewportHeight: 812,
                expandedPlayerHeight: 420,
                minimumPlayerHeight: 236
            ),
            996
        )
    }

    @MainActor
    func testInteractiveScrollMetricsSeparatePlayerCollapseFromContentScroll() {
        let metrics = VideoDetailShellLayout.interactiveScrollMetrics(
            scrollOffset: 120,
            expandedPlayerHeight: 420,
            minimumPlayerHeight: 236
        )

        XCTAssertEqual(metrics.collapseOffset, 120)
        XCTAssertEqual(metrics.contentOffset, 0)
        XCTAssertFalse(metrics.isPlayerCollapsed)

        let collapsed = VideoDetailShellLayout.interactiveScrollMetrics(
            scrollOffset: 240,
            expandedPlayerHeight: 420,
            minimumPlayerHeight: 236
        )

        XCTAssertEqual(collapsed.collapseOffset, 184)
        XCTAssertEqual(collapsed.contentOffset, 56)
        XCTAssertTrue(collapsed.isPlayerCollapsed)
    }

    @MainActor
    func testInteractiveScrollMetricsKeepTheTotalOffsetContinuousAcrossTheMinimum() {
        let beforeMinimum = VideoDetailShellLayout.interactiveScrollMetrics(
            scrollOffset: 183,
            expandedPlayerHeight: 420,
            minimumPlayerHeight: 236
        )
        let afterMinimum = VideoDetailShellLayout.interactiveScrollMetrics(
            scrollOffset: 185,
            expandedPlayerHeight: 420,
            minimumPlayerHeight: 236
        )

        XCTAssertEqual(beforeMinimum.collapseOffset, 183)
        XCTAssertEqual(beforeMinimum.contentOffset, 0)
        XCTAssertEqual(afterMinimum.collapseOffset, 184)
        XCTAssertEqual(afterMinimum.contentOffset, 1)
    }

    @MainActor
    func testVideoDetailInteractiveCollapseDoesNotShrinkPlayingLandscapeVideo() {
        let layout = VideoDetailShellLayout.resolve(
            bounds: CGRect(x: 0, y: 0, width: 420, height: 912),
            safeAreaTop: 62,
            videoAspectRatio: 16.0 / 9.0,
            currentPlayerHeight: VideoDetailShellLayout.collapsedToolbarHeight,
            isPlaybackActive: true,
            isLandscape: false,
            isPortraitFullscreen: false
        )

        XCTAssertEqual(
            layout.playerFrame.height,
            VideoDetailShellLayout.standardPlayerHeight(forWidth: 420)
        )
        XCTAssertEqual(layout.contentTopInset, layout.playerFrame.height)
    }

    @MainActor
    func testVideoDetailInteractiveCollapseAllowsPausedLandscapeVideoToReachToolbarHeight() {
        let layout = VideoDetailShellLayout.resolve(
            bounds: CGRect(x: 0, y: 0, width: 420, height: 912),
            safeAreaTop: 62,
            videoAspectRatio: 16.0 / 9.0,
            currentPlayerHeight: 0,
            isPlaybackActive: false,
            isLandscape: false,
            isPortraitFullscreen: false
        )

        XCTAssertEqual(layout.playerFrame.height, VideoDetailShellLayout.collapsedToolbarHeight)
        XCTAssertTrue(
            VideoDetailShellLayout.supportsInteractiveCollapse(
                videoAspectRatio: 16.0 / 9.0,
                isPlaybackActive: false
            )
        )
        XCTAssertFalse(
            VideoDetailShellLayout.supportsInteractiveCollapse(
                videoAspectRatio: 16.0 / 9.0,
                isPlaybackActive: true
            )
        )
    }

    @MainActor
    func testPlaybackRotationCoordinatorCoalescesRequestsAndPublishesStablePhase() {
        let coordinator = PlaybackRotationCoordinator()
        coordinator.activate(isLandscape: false)
        coordinator.beginSystemTransition(toLandscape: true)
        XCTAssertEqual(coordinator.phase, .preparingLandscape)
        XCTAssertFalse(
            coordinator.requestGeometryUpdate(to: .landscapeLeft, in: nil)
        )
        XCTAssertFalse(
            coordinator.requestGeometryUpdate(to: .landscapeRight, in: nil)
        )
        XCTAssertFalse(
            coordinator.requestGeometryUpdate(to: .portrait, in: nil)
        )
        XCTAssertEqual(coordinator.pendingTarget, .portrait)

        XCTAssertEqual(
            coordinator.finishSystemTransition(
                toLandscape: true,
                currentOrientation: .landscapeRight
            ),
            .portrait
        )
        XCTAssertEqual(coordinator.phase, .landscape)
        XCTAssertFalse(coordinator.isSystemRotationTransitioning)
        XCTAssertTrue(coordinator.isLandscape)
        XCTAssertTrue(coordinator.layoutLandscape)
        XCTAssertTrue(coordinator.chromeLandscape)
    }

    @MainActor
    func testPlaybackRotationCoordinatorUsesTargetDirectionForLayoutDuringTransition() {
        let coordinator = PlaybackRotationCoordinator()
        coordinator.activate(isLandscape: true)

        coordinator.beginSystemTransition(toLandscape: false)

        XCTAssertTrue(coordinator.isLandscape)
        XCTAssertFalse(coordinator.layoutLandscape)
        XCTAssertTrue(coordinator.chromeLandscape)

        coordinator.finishSystemTransition(
            toLandscape: false,
            currentOrientation: .portrait
        )

        XCTAssertFalse(coordinator.isLandscape)
        XCTAssertFalse(coordinator.layoutLandscape)
        XCTAssertFalse(coordinator.chromeLandscape)
    }

    @MainActor
    func testSystemRotationNotifiesOuterToolbarWithoutFullscreenButton() throws {
        let dependencies = AppDependencies()
        let video = try JSONDecoder.bili.decode(VideoItem.self, from: Data(
            #"{"bvid":"BVRotationToolbarProbe","title":"旋转工具栏测试","dimension":{"width":1920,"height":1080}}"#.utf8
        ))
        let model = VideoDetailViewModel(seedVideo: video, api: dependencies.api,
            libraryStore: dependencies.libraryStore, sessionStore: dependencies.sessionStore,
            sponsorBlockService: dependencies.sponsorBlockService)
        let runtime = VideoDetailRuntimeSettingsStore()
        runtime.bind(dependencies.libraryStore)
        var visibilityChanges = [Bool]()
        let bridge = VideoDetailRotationBridgeViewController(
            initialVideo: video, viewModel: model, runtimeSettings: runtime, dependencies: dependencies,
            openVideoOwnerRoute: nil, selectedContentTab: .constant(.detail),
            onShowNetworkDiagnostics: {}, onShowFavoriteFolders: {}, onShowCoinPicker: {},
            onOpenCommentComposer: { _ in }, onShowDanmakuSettings: {},
            onPresentPlayerMoreControls: { _, _ in }, onDismissPlayerMoreControls: {}, onReply: { _ in },
            onSystemChromeVisibilityChange: { visibilityChanges.append($0) }, onNavigateBack: {}
        )
        defer { bridge.prepareForDismantle(); model.stopPlaybackForNavigation() }
        let transition = ToolbarRotationTestCoordinator()
        bridge.viewWillTransition(to: CGSize(width: 844, height: 390), with: transition)
        XCTAssertEqual(visibilityChanges, [true], "System rotation must hide the outer toolbar")
        XCTAssertTrue(bridge.prefersStatusBarHidden)
        // Landscape direction changes must keep it hidden without republishing.
        bridge.viewWillTransition(to: CGSize(width: 844, height: 390), with: transition)
        XCTAssertEqual(visibilityChanges, [true])
        bridge.viewWillTransition(to: CGSize(width: 390, height: 844), with: transition)
        XCTAssertEqual(visibilityChanges, [true, false], "Returning to portrait must restore the toolbar")
        XCTAssertFalse(bridge.prefersStatusBarHidden)
        // A rapid reversal should hide it again before the first layout frame.
        bridge.viewWillTransition(to: CGSize(width: 844, height: 390), with: transition)
        XCTAssertEqual(visibilityChanges, [true, false, true])
        bridge.prepareForDismantle()
        XCTAssertEqual(visibilityChanges, [true, false, true, false], "Exiting mid-rotation must release hidden chrome")
    }

    @MainActor
    func testPortraitFullscreenDoesNotRequestSystemRotation() {
        let coordinator = PlaybackRotationCoordinator()
        coordinator.activate(isLandscape: false)

        coordinator.setPortraitFullscreen(true)

        XCTAssertEqual(coordinator.phase, .portraitFullscreen)
        XCTAssertTrue(coordinator.isPortraitFullscreen)
        XCTAssertFalse(coordinator.isSystemRotationTransitioning)

        coordinator.setPortraitFullscreen(false)

        XCTAssertEqual(coordinator.phase, .embedded)
        XCTAssertFalse(coordinator.isPortraitFullscreen)
    }

    @MainActor
    func testPlaybackRotationCoordinatorRecoversToStableStateAfterInterruptedTransition() {
        let coordinator = PlaybackRotationCoordinator()
        coordinator.activate(isLandscape: false)
        coordinator.beginSystemTransition(toLandscape: true)

        coordinator.recover(isLandscape: false)

        XCTAssertEqual(coordinator.phase, .embedded)
        XCTAssertFalse(coordinator.isSystemRotationTransitioning)
        XCTAssertFalse(coordinator.isTransitioning)
        XCTAssertNil(coordinator.pendingTarget)
    }

    @MainActor
    func testPlaybackRotationCoordinatorDeactivationClearsFullscreenAndRestoresInactiveState() {
        let coordinator = PlaybackRotationCoordinator()
        coordinator.activate(isLandscape: false)
        coordinator.setPortraitFullscreen(true)

        coordinator.deactivate(in: nil)

        XCTAssertEqual(coordinator.phase, .embedded)
        XCTAssertFalse(coordinator.isPortraitFullscreen)
        XCTAssertFalse(coordinator.isViewActive)
        XCTAssertFalse(coordinator.isTransitioning)
    }

    func testRotationPolicyPreservesContentAndFreezesLayoutDuringTransition() {
        let policy = VideoDetailRotationPolicy()

        XCTAssertFalse(policy.hidesContentHost(duringTransitionToLandscape: true))
        XCTAssertFalse(policy.hidesContentHost(duringTransitionToLandscape: false))
        XCTAssertFalse(policy.publishesContentLayoutDuringSystemTransition)
        XCTAssertTrue(policy.hidesPlaybackControlsDuringSystemTransition)
        XCTAssertTrue(
            policy.usesPrewarmedFastRecovery(hasPrewarmedRotationChrome: true)
        )
        XCTAssertFalse(
            policy.usesPrewarmedFastRecovery(hasPrewarmedRotationChrome: false)
        )
        XCTAssertTrue(
            policy.restoresPortraitAfterResolvingPortraitVideo(isCurrentlyLandscape: true)
        )
        XCTAssertFalse(
            policy.restoresPortraitAfterResolvingPortraitVideo(isCurrentlyLandscape: false)
        )
    }

    func testRotationPolicyPreservesCurrentLandscapeOrUsesDeviceDirection() {
        let policy = VideoDetailRotationPolicy()

        XCTAssertEqual(
            policy.preferredLandscapeInterfaceOrientation(
                currentInterfaceOrientation: .landscapeLeft,
                deviceOrientation: .landscapeRight
            ),
            .landscapeLeft
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

    func testRotationRecoveryWatchdogAllowsCoordinatorAndRecoveryFramesToFinish() {
        let policy = VideoDetailRotationRecoveryPolicy()

        XCTAssertEqual(policy.watchdogDelay(coordinatorDuration: 0), 1.25)
        XCTAssertEqual(policy.watchdogDelay(coordinatorDuration: 0.4), 1.25)
        XCTAssertEqual(policy.watchdogDelay(coordinatorDuration: 1), 1.75)
    }

    func testRotationRecoveryUsesInterfaceOrientationBeforeBoundsFallback() {
        let policy = VideoDetailRotationRecoveryPolicy()

        XCTAssertTrue(
            policy.resolvesLandscape(
                interfaceOrientation: .landscapeLeft,
                fallbackBounds: CGSize(width: 390, height: 844)
            )
        )
        XCTAssertFalse(
            policy.resolvesLandscape(
                interfaceOrientation: .portrait,
                fallbackBounds: CGSize(width: 844, height: 390)
            )
        )
        XCTAssertTrue(
            policy.resolvesLandscape(
                interfaceOrientation: .unknown,
                fallbackBounds: CGSize(width: 844, height: 390)
            )
        )
    }

    func testFullscreenStatusControlsOnlyAppearOutsidePortraitFullscreen() {
        XCTAssertTrue(
            VideoDetailSurfaceChromePolicy.showsFullscreenStatusControls(
                usesFullscreenChrome: true,
                isPortraitFullscreen: false
            )
        )
        XCTAssertFalse(
            VideoDetailSurfaceChromePolicy.showsFullscreenStatusControls(
                usesFullscreenChrome: true,
                isPortraitFullscreen: true
            )
        )
        XCTAssertFalse(
            VideoDetailSurfaceChromePolicy.showsFullscreenStatusControls(
                usesFullscreenChrome: false,
                isPortraitFullscreen: false
            )
        )
    }

    func testRotationRequestCoalescerKeepsOnlyLatestTargetDuringTransition() {
        var coalescer = VideoDetailRotationRequestCoalescer()

        coalescer.beginTransition()
        XCTAssertNil(coalescer.submit(.landscapeLeft))
        XCTAssertNil(coalescer.submit(.landscapeRight))
        XCTAssertNil(coalescer.submit(.portrait))
        XCTAssertEqual(coalescer.pendingTarget, .portrait)
        XCTAssertEqual(
            coalescer.completeTransition(
                currentOrientation: .landscapeLeft
            ),
            .portrait
        )
        XCTAssertFalse(coalescer.isTransitioning)
        XCTAssertNil(coalescer.pendingTarget)
    }

    func testRotationRequestCoalescerDropsSatisfiedTarget() {
        var coalescer = VideoDetailRotationRequestCoalescer()

        coalescer.beginTransition()
        XCTAssertNil(coalescer.submit(.landscapeRight))
        XCTAssertNil(
            coalescer.completeTransition(
                currentOrientation: .landscapeRight
            )
        )
        XCTAssertFalse(coalescer.isTransitioning)
        XCTAssertNil(coalescer.pendingTarget)
    }

    func testRotationRequestCoalescerResetClearsTransitionAndPendingTarget() {
        var coalescer = VideoDetailRotationRequestCoalescer()

        coalescer.beginTransition()
        XCTAssertNil(coalescer.submit(.portrait))
        coalescer.reset()

        XCTAssertFalse(coalescer.isTransitioning)
        XCTAssertNil(coalescer.pendingTarget)
        XCTAssertEqual(coalescer.submit(.landscapeLeft), .landscapeLeft)
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

    private enum LayoutWaitError: Error { case timedOut }

    @MainActor
    private func waitUntil(
        _ stage: String = "shared layout",
        timeout: Duration = .seconds(10),
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else {
                XCTFail("Timed out waiting for shared playback detail state: \(stage)", file: file, line: line)
                throw LayoutWaitError.timedOut
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

/// Drives the real rotation callback without rotating the test runner's window.
@MainActor
private final class ToolbarRotationTestCoordinator: NSObject, UIViewControllerTransitionCoordinator {
    let isAnimated = true
    let presentationStyle = UIModalPresentationStyle.none
    let initiallyInteractive = false
    let isInterruptible = false
    let isInteractive = false
    let isCancelled = false
    let transitionDuration: TimeInterval = 0.3
    let percentComplete: CGFloat = 0
    let completionVelocity: CGFloat = 1
    let completionCurve = UIView.AnimationCurve.easeInOut
    let containerView = UIView()
    let targetTransform = CGAffineTransform.identity

    func viewController(forKey key: UITransitionContextViewControllerKey) -> UIViewController? { nil }
    func view(forKey key: UITransitionContextViewKey) -> UIView? { nil }

    func animate(alongsideTransition animation: ((any UIViewControllerTransitionCoordinatorContext) -> Void)?,
                 completion: ((any UIViewControllerTransitionCoordinatorContext) -> Void)?) -> Bool {
        // Keep the transition pending so the test can drive consecutive targets.
        true
    }

    func animateAlongsideTransition(in view: UIView?,
                                    animation: ((any UIViewControllerTransitionCoordinatorContext) -> Void)?,
                                    completion: ((any UIViewControllerTransitionCoordinatorContext) -> Void)?) -> Bool { true }

    func notifyWhenInteractionEnds(_ handler: @escaping (any UIViewControllerTransitionCoordinatorContext) -> Void) {}
    func notifyWhenInteractionChanges(_ handler: @escaping (any UIViewControllerTransitionCoordinatorContext) -> Void) {}
}
