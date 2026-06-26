import SwiftUI

struct VideoDetailStandardPlaybackContentLayer<DetailContent: View>: View {
    let config: VideoDetailStandardPlaybackPageConfig
    let layout: VideoDetailStandardPlaybackPageLayout
    @Binding var selectedContentTab: VideoDetailContentTab
    let onScrollOffsetChange: (VideoDetailContentTab, CGFloat) -> Void
    let detailContent: (VideoDetailContentTab) -> DetailContent

    var body: some View {
        VideoDetailStandardContentLayer(
            config: config,
            layout: layout,
            selectedContentTab: $selectedContentTab,
            onScrollOffsetChange: onScrollOffsetChange,
            detailContent: detailContent
        )
    }
}
