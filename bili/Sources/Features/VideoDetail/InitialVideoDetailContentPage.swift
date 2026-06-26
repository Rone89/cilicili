import SwiftUI

struct InitialVideoDetailContentPage: View {
    let seedVideo: VideoItem
    let layoutWidth: CGFloat
    let tab: VideoDetailContentTab

    var body: some View {
        VStack(alignment: .leading, spacing: VideoDetailContentPageMetrics.spacing) {
            InitialVideoDetailContentPageBody(
                seedVideo: seedVideo,
                layoutWidth: layoutWidth,
                tab: tab
            )
        }
        .padding(.top, VideoDetailContentPageMetrics.topPadding)
        .frame(width: layoutWidth, alignment: .top)
        .background(VideoDetailTheme.background)
    }
}
