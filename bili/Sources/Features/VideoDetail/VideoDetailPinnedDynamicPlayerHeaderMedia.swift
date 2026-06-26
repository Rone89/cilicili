import SwiftUI

struct VideoDetailPinnedDynamicPlayerHeaderMedia: View {
    let config: VideoDetailPinnedDynamicPlayerHeaderConfig
    let playerHeight: CGFloat
    let usesCollapsedChrome: Bool
    @ObservedObject var playerIdentityStore: VideoDetailPlayerIdentityRenderStore
    let stores: VideoDetailPinnedDynamicPlayerHeaderStores
    let selectPlayVariant: (PlayVariant) -> Void
    let onToggleDanmaku: () -> Void
    let onPrepareForUserSeek: (Double) -> Void
    let onDanmakuPlaybackTime: (TimeInterval, Bool) -> Void
    let onNavigateBack: () -> Void

    var body: some View {
        if let playerViewModel = playerIdentityStore.playerViewModel {
            VideoDetailPinnedLoadedPlayerMedia(
                config: config,
                playerHeight: playerHeight,
                usesCollapsedChrome: usesCollapsedChrome,
                playerIdentityStore: playerIdentityStore,
                stores: stores,
                playerViewModel: playerViewModel,
                selectPlayVariant: selectPlayVariant,
                onToggleDanmaku: onToggleDanmaku,
                onPrepareForUserSeek: onPrepareForUserSeek,
                onDanmakuPlaybackTime: onDanmakuPlaybackTime,
                onNavigateBack: onNavigateBack
            )
        } else {
            VideoDetailPinnedPlaceholderPlayerMedia(
                config: config,
                playerHeight: playerHeight,
                stores: stores,
                onNavigateBack: onNavigateBack
            )
        }
    }
}
