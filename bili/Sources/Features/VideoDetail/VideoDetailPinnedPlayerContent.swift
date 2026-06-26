import SwiftUI

struct VideoDetailPinnedPlayerContent: View {
    @ObservedObject var playerIdentityStore: VideoDetailPlayerIdentityRenderStore
    let stores: VideoDetailPinnedDynamicPlayerHeaderStores
    let playerViewModel: PlayerStateViewModel
    let configuration: VideoDetailPinnedPlayerContentConfiguration
    let actions: VideoDetailPinnedPlayerContentActions

    var body: some View {
        ZStack {
            VideoDetailPlayerSurface(
                surfaceStore: stores.surfaceStore,
                qualityControlStore: stores.qualityControlStore,
                danmakuStore: stores.danmakuStore,
                playerViewModel: playerViewModel,
                configuration: configuration.surfaceConfiguration,
                actions: actions.surfaceActions,
                allowsPlaybackActivation: allowsPlaybackActivation
            )

            VideoDetailPinnedCollapsedChromeOverlay(
                playerViewModel: playerViewModel,
                isPresented: configuration.usesCollapsedChrome,
                onNavigateBack: actions.onNavigateBack,
                onRequestFullscreen: requestFullscreen
            )
        }
        .animation(
            VideoDetailFullscreenCoordinator.inlineTransitionAnimation,
            value: playerIdentityStore.transitionPlayerOpacity
        )
    }

    private func requestFullscreen() {
        actions.requestFullscreen(for: playerViewModel)
    }

    private func allowsPlaybackActivation() -> Bool {
        playerIdentityStore.playerViewModel === playerViewModel
            && !playerViewModel.isTerminated
    }
}
