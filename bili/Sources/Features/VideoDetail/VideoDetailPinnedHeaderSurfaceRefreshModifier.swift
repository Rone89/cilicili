import SwiftUI

private struct VideoDetailPinnedHeaderSurfaceRefreshModifier: ViewModifier {
    let playerHeight: CGFloat
    let playerIdentityKey: ObjectIdentifier?
    let actions: VideoDetailPinnedHeaderSurfaceRefreshActions

    func body(content: Content) -> some View {
        content
            .onAppear(perform: actions.schedule)
            .onChange(of: playerHeight) { _, _ in
                actions.schedule()
            }
            .onChange(of: playerIdentityKey) { _, _ in
                actions.cancel()
                actions.schedule()
            }
            .onDisappear(perform: actions.cancel)
    }
}

extension View {
    func videoDetailPinnedHeaderSurfaceRefresh(
        playerHeight: CGFloat,
        playerIdentityStore: VideoDetailPlayerIdentityRenderStore,
        surfaceRefreshCoordinator: VideoDetailPinnedDynamicPlayerHeaderSurfaceRefreshCoordinator
    ) -> some View {
        modifier(
            VideoDetailPinnedHeaderSurfaceRefreshModifier(
                playerHeight: playerHeight,
                playerIdentityKey: playerIdentityStore.playerViewModel.map(ObjectIdentifier.init),
                actions: VideoDetailPinnedHeaderSurfaceRefreshActions(
                    playerIdentityStore: playerIdentityStore,
                    surfaceRefreshCoordinator: surfaceRefreshCoordinator
                )
            )
        )
    }
}
