import SwiftUI

struct VideoDetailPinnedDynamicPlayerHeaderChrome: ViewModifier {
    @ObservedObject var playerIdentityStore: VideoDetailPlayerIdentityRenderStore
    let surfaceRefreshCoordinator: VideoDetailPinnedDynamicPlayerHeaderSurfaceRefreshCoordinator
    let config: VideoDetailPinnedDynamicPlayerHeaderConfig
    let context: VideoDetailPinnedDynamicPlayerHeaderContext
    let onPrepareForUserSeek: (Double) -> Void

    func body(content: Content) -> some View {
        content
            .videoDetailPinnedDynamicPlayerHeaderLayoutChrome(
                playerWidth: config.playerWidth,
                renderState: context.renderState,
                isLayoutTransitioning: config.isLayoutTransitioning
            )
            .videoDetailPinnedDynamicPlayerHeaderProgressChrome(
                playerIdentityStore: playerIdentityStore,
                context: context,
                onPrepareForUserSeek: onPrepareForUserSeek
            )
            .videoDetailPinnedDynamicPlayerHeaderLifecycleChrome(
                playerIdentityStore: playerIdentityStore,
                surfaceRefreshCoordinator: surfaceRefreshCoordinator,
                context: context
            )
    }
}

extension View {
    func videoDetailPinnedDynamicPlayerHeaderChrome(
        playerIdentityStore: VideoDetailPlayerIdentityRenderStore,
        surfaceRefreshCoordinator: VideoDetailPinnedDynamicPlayerHeaderSurfaceRefreshCoordinator,
        config: VideoDetailPinnedDynamicPlayerHeaderConfig,
        context: VideoDetailPinnedDynamicPlayerHeaderContext,
        onPrepareForUserSeek: @escaping (Double) -> Void
    ) -> some View {
        modifier(
            VideoDetailPinnedDynamicPlayerHeaderChrome(
                playerIdentityStore: playerIdentityStore,
                surfaceRefreshCoordinator: surfaceRefreshCoordinator,
                config: config,
                context: context,
                onPrepareForUserSeek: onPrepareForUserSeek
            )
        )
    }
}
