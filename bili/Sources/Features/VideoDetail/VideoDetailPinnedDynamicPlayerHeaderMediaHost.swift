import SwiftUI

struct VideoDetailPinnedDynamicPlayerHeaderMediaHost: View {
    let config: VideoDetailPinnedDynamicPlayerHeaderConfig
    let context: VideoDetailPinnedDynamicPlayerHeaderContext
    @ObservedObject var playerIdentityStore: VideoDetailPlayerIdentityRenderStore
    let stores: VideoDetailPinnedDynamicPlayerHeaderStores
    let selectPlayVariant: (PlayVariant) -> Void
    let onToggleDanmaku: () -> Void
    let onPrepareForUserSeek: (Double) -> Void
    let onDanmakuPlaybackTime: (TimeInterval, Bool) -> Void

    var body: some View {
        VideoDetailPinnedDynamicPlayerHeaderMedia(
            config: config,
            playerHeight: context.renderState.playerHeight,
            usesCollapsedChrome: context.renderState.usesCollapsedChrome,
            playerIdentityStore: playerIdentityStore,
            stores: stores,
            selectPlayVariant: selectPlayVariant,
            onToggleDanmaku: onToggleDanmaku,
            onPrepareForUserSeek: onPrepareForUserSeek,
            onDanmakuPlaybackTime: onDanmakuPlaybackTime,
            onNavigateBack: context.navigationActions.handleBackButtonTap
        )
    }
}
