import SwiftUI

struct VideoDetailNativeContentTabPage<Content: View>: View {
    let tab: VideoDetailContentTab
    let layoutWidth: CGFloat
    let topInset: CGFloat
    let onScrollOffsetChange: (VideoDetailContentTab, CGFloat) -> Void
    let content: (VideoDetailContentTab) -> Content

    var body: some View {
        VideoDetailNativeScrollTabPage(
            tab: tab,
            layoutWidth: layoutWidth,
            topInset: topInset,
            onScrollOffsetChange: onScrollOffsetChange,
            content: content
        )
    }
}
