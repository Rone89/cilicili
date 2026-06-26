import SwiftUI

struct VideoDetailPinnedDynamicPlayerHeaderLifecycleChrome: ViewModifier {
    @ObservedObject var playerIdentityStore: VideoDetailPlayerIdentityRenderStore
    let surfaceRefreshCoordinator: VideoDetailPinnedDynamicPlayerHeaderSurfaceRefreshCoordinator
    let context: VideoDetailPinnedDynamicPlayerHeaderContext

    func body(content: Content) -> some View {
        content
            .videoDetailPinnedHeaderSurfaceRefresh(
                playerHeight: context.renderState.playerHeight,
                playerIdentityStore: playerIdentityStore,
                surfaceRefreshCoordinator: surfaceRefreshCoordinator
            )
            .videoDetailPlaybackActivityBridge(
                playerViewModel: playerIdentityStore.playerViewModel,
                playerIdentityStore: playerIdentityStore,
                playbackActions: context.playbackActions
            )
    }
}
