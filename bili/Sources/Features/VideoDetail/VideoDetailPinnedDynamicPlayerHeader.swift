import SwiftUI

struct VideoDetailPinnedDynamicPlayerHeader: View {
    let config: VideoDetailPinnedDynamicPlayerHeaderConfig
    let layout: VideoDetailPinnedDynamicPlayerHeaderLayout
    let scrollOffset: CGFloat
    @Binding var isPlaybackActive: Bool
    @ObservedObject var playerIdentityStore: VideoDetailPlayerIdentityRenderStore
    let stores: VideoDetailPinnedDynamicPlayerHeaderStores
    let selectPlayVariant: (PlayVariant) -> Void
    let onToggleDanmaku: () -> Void
    let onPrepareForUserSeek: (Double) -> Void
    let onDanmakuPlaybackTime: (TimeInterval, Bool) -> Void
    @State private var surfaceRefreshCoordinator = VideoDetailPinnedDynamicPlayerHeaderSurfaceRefreshCoordinator()

    var body: some View {
        let context = headerContext

        ZStack(alignment: .top) {
            VideoDetailPinnedDynamicPlayerHeaderMediaHost(
                config: config,
                context: context,
                playerIdentityStore: playerIdentityStore,
                stores: stores,
                selectPlayVariant: selectPlayVariant,
                onToggleDanmaku: onToggleDanmaku,
                onPrepareForUserSeek: onPrepareForUserSeek,
                onDanmakuPlaybackTime: onDanmakuPlaybackTime
            )
            .zIndex(0)

            VideoDetailPinnedDynamicPlayerHeaderChromeHost(
                playerIdentityStore: playerIdentityStore,
                surfaceRefreshCoordinator: surfaceRefreshCoordinator,
                config: config,
                context: context,
                onPrepareForUserSeek: onPrepareForUserSeek
            )
            .zIndex(1)
        }
        .videoDetailPinnedDynamicPlayerHeaderLayoutChrome(
            playerWidth: config.playerWidth,
            renderState: context.renderState,
            isLayoutTransitioning: config.isLayoutTransitioning
        )
    }

    private var headerContext: VideoDetailPinnedDynamicPlayerHeaderContext {
        VideoDetailPinnedDynamicPlayerHeaderContext(
            config: config,
            layout: layout,
            scrollOffset: scrollOffset,
            isPlaybackActive: $isPlaybackActive
        )
    }
}
