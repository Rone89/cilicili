import SwiftUI

extension View {
    func videoDetailPinnedDynamicPlayerHeaderLayoutChrome(
        playerWidth: CGFloat?,
        renderState: VideoDetailPinnedDynamicPlayerHeaderRenderState,
        isLayoutTransitioning: Bool
    ) -> some View {
        modifier(
            VideoDetailPinnedDynamicPlayerHeaderLayoutChrome(
                playerWidth: playerWidth,
                renderState: renderState,
                isLayoutTransitioning: isLayoutTransitioning
            )
        )
    }

    func videoDetailPinnedDynamicPlayerHeaderProgressChrome(
        playerIdentityStore: VideoDetailPlayerIdentityRenderStore,
        context: VideoDetailPinnedDynamicPlayerHeaderContext,
        onPrepareForUserSeek: @escaping (Double) -> Void
    ) -> some View {
        modifier(
            VideoDetailPinnedDynamicPlayerHeaderProgressChrome(
                playerIdentityStore: playerIdentityStore,
                context: context,
                onPrepareForUserSeek: onPrepareForUserSeek
            )
        )
    }

    func videoDetailPinnedDynamicPlayerHeaderLifecycleChrome(
        playerIdentityStore: VideoDetailPlayerIdentityRenderStore,
        surfaceRefreshCoordinator: VideoDetailPinnedDynamicPlayerHeaderSurfaceRefreshCoordinator,
        context: VideoDetailPinnedDynamicPlayerHeaderContext
    ) -> some View {
        modifier(
            VideoDetailPinnedDynamicPlayerHeaderLifecycleChrome(
                playerIdentityStore: playerIdentityStore,
                surfaceRefreshCoordinator: surfaceRefreshCoordinator,
                context: context
            )
        )
    }
}
