import SwiftUI

struct VideoDetailStandardContentLayer<DetailContent: View>: View {
    let config: VideoDetailStandardPlaybackPageConfig
    let layout: VideoDetailStandardPlaybackPageLayout
    @Binding var selectedContentTab: VideoDetailContentTab
    let onScrollOffsetChange: (VideoDetailContentTab, CGFloat) -> Void
    let detailContent: (VideoDetailContentTab) -> DetailContent

    var body: some View {
        if !config.isLandscape {
            VideoDetailNativeContentTabView(
                selection: $selectedContentTab,
                layoutWidth: config.screenSize.width,
                topInset: layout.headerLayout.expandedHeight,
                minimizesTabBarOnScroll: config.minimizesTabBarOnScroll,
                onScrollOffsetChange: onScrollOffsetChange,
                content: detailContent
            )
            .frame(
                width: config.screenSize.width,
                height: config.screenSize.height,
                alignment: .top
            )
            .opacity(layout.hidesPortraitContent ? 0 : 1)
            .allowsHitTesting(!config.isFullscreen)
            .animation(
                config.isLayoutTransitioning ? nil : VideoDetailFullscreenCoordinator.inlineTransitionAnimation,
                value: layout.hidesPortraitContent
            )
        }
    }
}
