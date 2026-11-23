import SwiftUI
import UIKit

struct LiveRoomContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject var libraryStore: LibraryStore
    @ObservedObject var viewModel: LiveRoomViewModel
    @State var fullscreenMode: PlayerFullscreenMode?
    @State var isCompletingFullscreenExit = false
    @State var pendingFullscreenExitTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            let layout = LiveRoomContentLayout(
                proxySize: proxy.size,
                fullscreenGeometry: proxy.liveDetailFullscreenContainerGeometry,
                fullscreenMode: fullscreenMode,
                isCompletingFullscreenExit: isCompletingFullscreenExit,
                horizontalSizeClass: horizontalSizeClass
            )

            liveStageContent(layout: layout, proxySize: proxy.size)
            .frame(
                width: layout.frameSize.width,
                height: layout.frameSize.height
            )
            .offset(layout.frameOffset)
            .background(layout.isLandscape ? Color.black : VideoDetailTheme.background)
            .ignoresSafeArea(.container, edges: layout.ignoresContainerSafeArea ? .all : [])
            .preference(key: PlaybackDetailChromeHiddenPreferenceKey.self, value: layout.shouldHideSystemChrome)
            .onChange(of: "\(layout.isLandscape)|\(layout.isInlineFullscreen)") { _, _ in
                PlaybackDetailPerformanceMonitor.shared.mark(
                    .fullscreenLayoutUpdated,
                    context: performanceContext,
                    detail: "landscape=\(layout.isLandscape) inline=\(layout.isInlineFullscreen)"
                )
            }
        }
        .background(VideoDetailTheme.background)
        .overlay {
            if let fullPageFailureMessage {
                ErrorStateView(
                    title: "直播加载失败",
                    message: fullPageFailureMessage,
                    retry: viewModel.reload
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(VideoDetailTheme.background.opacity(0.96))
            }
        }
        .onAppear {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            allowLiveAutoRotation()
            updateLiveFullscreenOrientation(UIDevice.current.orientation)
        }
        .onDisappear {
            pendingFullscreenExitTask?.cancel()
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            AppOrientationLock.restorePortrait()
            fullscreenMode = nil
            isCompletingFullscreenExit = false
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, fullscreenMode == nil else { return }
            allowLiveAutoRotation()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            updateLiveFullscreenOrientation(UIDevice.current.orientation)
        }
        .ignoresSafeArea(.container, edges: (fullscreenMode != nil || isCompletingFullscreenExit) ? .all : [])
    }

    private var fullPageFailureMessage: String? {
        guard case .failed(let message) = viewModel.state, viewModel.playerViewModel == nil else {
            return nil
        }
        return message
    }

    var performanceContext: PlaybackDetailPerformanceContext {
        .live(roomID: viewModel.roomID, title: viewModel.title)
    }

    private func liveStageContent(
        layout: LiveRoomContentLayout,
        proxySize: CGSize
    ) -> some View {
        let isSplit = layout.isSplitTwoColumn
        let split = AdaptiveLayoutPolicy.videoDetailSplitColumnWidths(totalWidth: proxySize.width)
        let standardPlayerHeight = PlaybackDetailPlayerMetrics.standardHeight(for: layout.screenSize.width)
        let expandsToFullscreen = layout.isLandscape || layout.isInlineFullscreen
        let splitPlayerHeight = min(max(proxySize.height - 40, 240), (split.playerColumnWidth * 9 / 16).rounded())

        let playerWidth: CGFloat? = isSplit
            ? split.playerColumnWidth
            : (layout.isLandscape ? layout.screenSize.width : nil)
        let playerHeight: CGFloat = expandsToFullscreen
            ? layout.screenSize.height
            : (isSplit ? splitPlayerHeight : standardPlayerHeight)
        let playerStageWidth: CGFloat = isSplit ? split.playerColumnWidth : layout.screenSize.width
        let playerStageHeight: CGFloat = isSplit ? proxySize.height : playerHeight
        let playerOriginY: CGFloat = isSplit ? max((proxySize.height - playerHeight) / 2, 0) : 0

        let contentWidth: CGFloat = isSplit ? split.contentColumnWidth : layout.screenSize.width
        let contentHeight: CGFloat = isSplit ? proxySize.height : layout.screenSize.height
        let contentOriginX: CGFloat = isSplit ? split.playerColumnWidth : 0
        let contentTopInset: CGFloat = isSplit ? 0 : standardPlayerHeight

        return ZStack(alignment: .topLeading) {
            if !layout.isLandscape || isSplit {
                PlaybackDetailScrollPage(
                    layoutWidth: contentWidth,
                    topInset: contentTopInset,
                    background: VideoDetailTheme.background
                ) {
                    detailScrollPage(viewModel, layoutWidth: contentWidth)
                        .frame(width: contentWidth, alignment: .top)
                }
                .frame(width: contentWidth, height: contentHeight)
                .offset(x: contentOriginX, y: 0)
                .opacity(layout.isInlineFullscreen ? 0 : 1)
                .allowsHitTesting(!layout.isInlineFullscreen)
            }

            if expandsToFullscreen {
                Color.black
                    .frame(width: layout.screenSize.width, height: layout.screenSize.height)
                    .allowsHitTesting(false)
            } else if isSplit {
                Color.black
                    .frame(width: playerStageWidth, height: playerStageHeight)
                    .allowsHitTesting(false)
            }

            playerHero(
                viewModel,
                isLandscape: layout.isLandscape,
                fullscreenMode: fullscreenMode,
                playerWidth: playerWidth,
                playerHeight: playerHeight
            )
            .offset(x: 0, y: expandsToFullscreen ? 0 : playerOriginY)
        }
        .frame(width: layout.screenSize.width, height: layout.screenSize.height, alignment: .topLeading)
        .background(expandsToFullscreen ? Color.black : VideoDetailTheme.background)
    }

    private func playerHero(
        _ viewModel: LiveRoomViewModel,
        isLandscape: Bool,
        fullscreenMode: PlayerFullscreenMode?,
        playerWidth: CGFloat?,
        playerHeight: CGFloat
    ) -> some View {
        LiveRoomPlayerHero(
            viewModel: viewModel,
            isLandscape: isLandscape,
            fullscreenMode: fullscreenMode,
            playerWidth: playerWidth,
            playerHeight: playerHeight,
            loadingPlaceholder: { AnyView(liveLoadingPlaceholder(viewModel)) },
            onRequestFullscreen: enterInlineFullscreenPlayback(playerViewModel:),
            onExitFullscreen: exitInlineFullscreenPlayback(playerViewModel:)
        )
    }
}
