import SwiftUI

struct VideoDetailStandardPlaybackResolvedPage<DetailContent: View>: View {
    let config: VideoDetailStandardPlaybackPageConfig
    let renderPack: VideoDetailStandardPlaybackPageRenderPack
    @Binding var selectedContentTab: VideoDetailContentTab
    @Binding var isPlaybackActive: Bool
    @ObservedObject var playerIdentityStore: VideoDetailPlayerIdentityRenderStore
    let onScrollOffsetChange: (VideoDetailContentTab, CGFloat) -> Void
    let detailContent: (VideoDetailContentTab) -> DetailContent

    var body: some View {
        VideoDetailStandardPlaybackPageBody(
            config: config,
            layout: renderPack.context.layout,
            selectedContentTab: $selectedContentTab,
            isPlaybackActive: $isPlaybackActive,
            playerIdentityStore: playerIdentityStore,
            stores: renderPack.headerStores,
            actions: renderPack.actions,
            onScrollOffsetChange: onScrollOffsetChange,
            detailContent: detailContent
        )
    }
}
