import SwiftUI

struct VideoDetailStandardPlaybackHeaderLayerHost: View {
    let config: VideoDetailStandardPlaybackPageConfig
    let layout: VideoDetailStandardPlaybackPageLayout
    @Binding var isPlaybackActive: Bool
    @ObservedObject var playerIdentityStore: VideoDetailPlayerIdentityRenderStore
    let stores: VideoDetailPinnedDynamicPlayerHeaderStores
    let actions: VideoDetailStandardPlaybackPageActions

    var body: some View {
        VideoDetailStandardPlayerHeaderLayer(
            config: config,
            layout: layout,
            scrollOffset: layout.selectedScrollOffset,
            isPlaybackActive: $isPlaybackActive,
            playerIdentityStore: playerIdentityStore,
            stores: stores,
            actions: actions
        )
    }
}
