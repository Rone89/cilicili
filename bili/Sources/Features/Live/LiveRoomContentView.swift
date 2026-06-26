import SwiftUI
import UIKit

struct LiveRoomContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var viewModel: LiveRoomViewModel
    @State var isShowingDescription = false
    @State var fullscreenMode: PlayerFullscreenMode?
    @State var isCompletingFullscreenExit = false
    @State var pendingFullscreenExitTask: Task<Void, Never>?

    static let supportedLiveOrientations: UIInterfaceOrientationMask = [
        .portrait,
        .landscapeLeft,
        .landscapeRight
    ]

    var body: some View {
        GeometryReader { proxy in
            let layout = LiveRoomContentLayout(
                proxySize: proxy.size,
                fullscreenGeometry: proxy.liveDetailFullscreenContainerGeometry,
                fullscreenMode: fullscreenMode,
                isCompletingFullscreenExit: isCompletingFullscreenExit
            )

            standardPlaybackPage(
                viewModel,
                screenSize: layout.screenSize,
                isLandscape: layout.isLandscape,
                isInlineFullscreen: layout.isInlineFullscreen
            )
            .frame(
                width: layout.frameSize.width,
                height: layout.frameSize.height
            )
            .offset(layout.frameOffset)
            .background(layout.isLandscape ? Color.black : VideoDetailTheme.background)
            .ignoresSafeArea(.container, edges: layout.ignoresContainerSafeArea ? .all : [])
            .preference(key: LiveDetailChromeHiddenPreferenceKey.self, value: layout.shouldHideSystemChrome)
            .statusBar(hidden: layout.shouldHideSystemChrome)
            .persistentSystemOverlays(layout.shouldHideSystemChrome ? .hidden : .automatic)
            .background {
                LiveStatusBarStyleBridge(
                    style: layout.ignoresContainerSafeArea ? .lightContent : .default,
                    isHidden: layout.shouldHideSystemChrome
                )
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
            }
        }
        .background(VideoDetailTheme.background)
        .overlay {
            if case .failed(let message) = viewModel.state, viewModel.playerViewModel == nil {
                ErrorStateView(title: "直播加载失败", message: message, retry: viewModel.reload)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(VideoDetailTheme.background.opacity(0.96))
            }
        }
        .task(id: viewModel.roomID) {
            viewModel.startLoading()
        }
        .onAppear {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            allowLiveAutoRotation()
            updateLiveFullscreenOrientation(UIDevice.current.orientation)
        }
        .onDisappear {
            pendingFullscreenExitTask?.cancel()
            viewModel.stopPlaybackForNavigation()
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            AppOrientationLock.restorePortrait()
            fullscreenMode = nil
            isCompletingFullscreenExit = false
        }
        .sheet(isPresented: $isShowingDescription) {
            LiveRoomDescriptionSheet(viewModel: viewModel)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                if fullscreenMode == nil {
                    allowLiveAutoRotation()
                }
                viewModel.resumeLiveDanmakuIfNeeded()
            case .background:
                viewModel.suspendLiveDanmaku()
            default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            updateLiveFullscreenOrientation(UIDevice.current.orientation)
        }
        .ignoresSafeArea(.container, edges: (fullscreenMode != nil || isCompletingFullscreenExit) ? .all : [])
    }

    private func standardPlaybackPage(
        _ viewModel: LiveRoomViewModel,
        screenSize: CGSize,
        isLandscape: Bool,
        isInlineFullscreen: Bool
    ) -> some View {
        let standardHeight = screenSize.width * 9 / 16
        let expandsToFullscreen = isLandscape || isInlineFullscreen
        let playerHeight = expandsToFullscreen ? screenSize.height : standardHeight
        let playerWidth: CGFloat? = isLandscape ? screenSize.width : nil

        return ZStack(alignment: .top) {
            VideoDetailTheme.background
                .opacity(expandsToFullscreen ? 0 : 1)
                .ignoresSafeArea()

            if !isLandscape {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: standardHeight)

                    ScrollView(.vertical) {
                        detailScrollPage(viewModel, layoutWidth: screenSize.width)
                            .frame(width: screenSize.width, alignment: .top)
                    }
                    .scrollIndicators(.hidden)
                    .nativeTopScrollEdgeEffect()
                    .frame(width: screenSize.width, alignment: .top)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .opacity(isInlineFullscreen ? 0 : 1)
                    .allowsHitTesting(!isInlineFullscreen)
                }
                .frame(width: screenSize.width, height: screenSize.height, alignment: .top)
            }

            if expandsToFullscreen {
                Color.black
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            playerHero(
                viewModel,
                isLandscape: isLandscape,
                fullscreenMode: fullscreenMode,
                playerWidth: playerWidth,
                playerHeight: playerHeight
            )
        }
        .frame(width: screenSize.width, height: screenSize.height)
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
            controlsAccessory: { AnyView(livePlayerAccessory(viewModel)) },
            loadingPlaceholder: { AnyView(liveLoadingPlaceholder(viewModel)) },
            onRequestFullscreen: enterInlineFullscreenPlayback(playerViewModel:),
            onExitFullscreen: exitInlineFullscreenPlayback(playerViewModel:)
        )
    }
}
