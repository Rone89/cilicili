import SwiftUI

struct VideoDetailPinnedLoadedPlayerMedia: View {
    @ObservedObject var playerIdentityStore: VideoDetailPlayerIdentityRenderStore
    let stores: VideoDetailPinnedDynamicPlayerHeaderStores
    let playerViewModel: PlayerStateViewModel
    let renderPack: VideoDetailPinnedLoadedPlayerMediaRenderPack

    init(
        config: VideoDetailPinnedDynamicPlayerHeaderConfig,
        playerHeight: CGFloat,
        usesCollapsedChrome: Bool,
        playerIdentityStore: VideoDetailPlayerIdentityRenderStore,
        stores: VideoDetailPinnedDynamicPlayerHeaderStores,
        playerViewModel: PlayerStateViewModel,
        selectPlayVariant: @escaping (PlayVariant) -> Void,
        onToggleDanmaku: @escaping () -> Void,
        onPrepareForUserSeek: @escaping (Double) -> Void,
        onDanmakuPlaybackTime: @escaping (TimeInterval, Bool) -> Void,
        onNavigateBack: @escaping () -> Void
    ) {
        self.playerIdentityStore = playerIdentityStore
        self.stores = stores
        self.playerViewModel = playerViewModel
        renderPack = VideoDetailPinnedLoadedPlayerMediaRenderPackBuilder(
            config: config,
            playerHeight: playerHeight,
            usesCollapsedChrome: usesCollapsedChrome,
            selectPlayVariant: selectPlayVariant,
            onToggleDanmaku: onToggleDanmaku,
            onPrepareForUserSeek: onPrepareForUserSeek,
            onDanmakuPlaybackTime: onDanmakuPlaybackTime,
            onNavigateBack: onNavigateBack
        )
        .renderPack
    }

    var body: some View {
        VideoDetailPinnedPlayerContent(
            playerIdentityStore: playerIdentityStore,
            stores: stores,
            playerViewModel: playerViewModel,
            configuration: renderPack.configuration,
            actions: renderPack.actions
        )
    }
}
