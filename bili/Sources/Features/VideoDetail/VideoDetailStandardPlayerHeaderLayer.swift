import SwiftUI

struct VideoDetailStandardPlayerHeaderLayer: View {
    let config: VideoDetailStandardPlaybackPageConfig
    let layout: VideoDetailStandardPlaybackPageLayout
    let scrollOffset: CGFloat
    @Binding var isPlaybackActive: Bool
    @ObservedObject var playerIdentityStore: VideoDetailPlayerIdentityRenderStore
    let stores: VideoDetailPinnedDynamicPlayerHeaderStores
    let actions: VideoDetailStandardPlaybackPageActions

    var body: some View {
        VideoDetailPinnedDynamicPlayerHeader(
            config: config.headerConfig,
            layout: layout.headerLayout,
            scrollOffset: scrollOffset,
            isPlaybackActive: $isPlaybackActive,
            playerIdentityStore: playerIdentityStore,
            stores: stores,
            selectPlayVariant: actions.selectPlayVariant,
            onToggleDanmaku: actions.toggleDanmaku,
            onPrepareForUserSeek: actions.prepareForUserSeek,
            onDanmakuPlaybackTime: actions.updateDanmakuPlaybackTime
        )
    }
}
