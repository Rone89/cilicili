import SwiftUI

struct InitialVideoDetailContentPageBody: View {
    let seedVideo: VideoItem
    let layoutWidth: CGFloat
    let tab: VideoDetailContentTab

    var body: some View {
        switch tab {
        case .detail:
            InitialVideoDetailDetailContentPage(
                seedVideo: seedVideo,
                layoutWidth: layoutWidth
            )

        case .comments:
            InitialVideoDetailCommentsContentPage()
        }
    }
}
