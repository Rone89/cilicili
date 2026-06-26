import SwiftUI

struct VideoDetailPinnedDynamicPlayerHeaderChromeHost: View {
    @ObservedObject var playerIdentityStore: VideoDetailPlayerIdentityRenderStore
    let surfaceRefreshCoordinator: VideoDetailPinnedDynamicPlayerHeaderSurfaceRefreshCoordinator
    let config: VideoDetailPinnedDynamicPlayerHeaderConfig
    let context: VideoDetailPinnedDynamicPlayerHeaderContext
    let onPrepareForUserSeek: (Double) -> Void

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
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
