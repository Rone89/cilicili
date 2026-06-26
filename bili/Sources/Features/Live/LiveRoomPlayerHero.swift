import SwiftUI

struct LiveRoomPlayerHero: View {
    @ObservedObject var viewModel: LiveRoomViewModel
    let isLandscape: Bool
    let fullscreenMode: PlayerFullscreenMode?
    let playerWidth: CGFloat?
    let playerHeight: CGFloat
    let controlsAccessory: () -> AnyView
    let loadingPlaceholder: () -> AnyView
    let onRequestFullscreen: (PlayerStateViewModel?) -> Void
    let onExitFullscreen: (PlayerStateViewModel?) -> Void

    var body: some View {
        ZStack {
            if let playerViewModel = viewModel.playerViewModel {
                livePlayer(playerViewModel)
            } else {
                loadingPlaceholder()
                    .frame(width: playerWidth)
                    .frame(height: playerHeight)
            }

            streamFallbackMessage

            if viewModel.isLiveDanmakuDiagnosticsEnabled {
                LiveDanmakuDiagnosticsOverlay(
                    store: viewModel.liveDanmakuRenderStore.diagnosticsStore,
                    usesLandscapeChrome: usesLandscapeChrome
                )
            }
        }
        .frame(width: playerWidth)
        .frame(maxWidth: .infinity)
        .frame(height: playerHeight)
        .background(Color.black)
        .zIndex(1)
        .clipped()
    }

    private var usesLandscapeChrome: Bool {
        isLandscape || fullscreenMode?.isLandscape == true
    }

    @ViewBuilder
    private var streamFallbackMessage: some View {
        if let message = viewModel.streamFallbackMessage, viewModel.playerViewModel?.hasPresentedPlayback != true {
            Text(message)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.black.opacity(0.56))
                .clipShape(Capsule())
        }
    }

    private func livePlayer(_ playerViewModel: PlayerStateViewModel) -> some View {
        BiliPlayerView(
            viewModel: playerViewModel,
            historyVideo: nil,
            historyCID: nil,
            options: BiliPlayerViewOptions(
                presentation: usesLandscapeChrome ? .fullScreen : .embedded,
                showsNavigationChrome: false,
                showsStartupLoadingIndicator: false,
                pausesOnDisappear: false,
                surfaceOverlay: AnyView(
                    LiveDanmakuOverlay(
                        store: viewModel.liveDanmakuRenderStore,
                        playerViewModel: playerViewModel,
                        usesLandscapeChrome: usesLandscapeChrome
                    )
                ),
                controlsAccessory: usesLandscapeChrome ? controlsAccessory() : nil,
                isDanmakuEnabled: viewModel.isDanmakuEnabled,
                onToggleDanmaku: {
                    viewModel.toggleDanmaku()
                },
                keepsPlayerSurfaceStable: true,
                fullscreenMode: fullscreenMode,
                onRequestFullscreen: {
                    onRequestFullscreen(playerViewModel)
                },
                onExitFullscreen: {
                    onExitFullscreen(playerViewModel)
                }
            )
        )
        .id(ObjectIdentifier(playerViewModel))
        .frame(width: playerWidth)
        .frame(height: playerHeight)
    }
}
