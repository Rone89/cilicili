import SwiftUI

struct VideoDetailStandardPlaybackPageBody<DetailContent: View>: View {
    let config: VideoDetailStandardPlaybackPageConfig
    let layout: VideoDetailStandardPlaybackPageLayout
    @Binding var selectedContentTab: VideoDetailContentTab
    @Binding var isPlaybackActive: Bool
    @ObservedObject var playerIdentityStore: VideoDetailPlayerIdentityRenderStore
    let stores: VideoDetailPinnedDynamicPlayerHeaderStores
    let actions: VideoDetailStandardPlaybackPageActions
    let onScrollOffsetChange: (VideoDetailContentTab, CGFloat) -> Void
    let detailContent: (VideoDetailContentTab) -> DetailContent

    var body: some View {
        ZStack(alignment: .top) {
            VideoDetailStandardPlaybackBackgroundLayer()

            VideoDetailStandardPlaybackContentLayer(
                config: config,
                layout: layout,
                selectedContentTab: $selectedContentTab,
                onScrollOffsetChange: onScrollOffsetChange,
                detailContent: detailContent
            )

            VideoDetailStandardPlaybackBackdropLayer(
                usesBlackBackdrop: layout.usesBlackBackdrop
            )

            headerLayerHost
                .zIndex(config.isFullscreen ? 10 : 1)
        }
        .frame(width: config.screenSize.width, height: config.screenSize.height)
        .animation(
            config.isLayoutTransitioning
                ? nil
                : VideoDetailFullscreenCoordinator.inlineTransitionAnimation,
            value: layout.headerLayout.expandedHeight
        )
    }

    private var headerLayerHost: some View {
        VideoDetailStandardPlaybackHeaderLayerHost(
            config: config,
            layout: layout,
            isPlaybackActive: $isPlaybackActive,
            playerIdentityStore: playerIdentityStore,
            stores: stores,
            actions: actions
        )
    }
}
