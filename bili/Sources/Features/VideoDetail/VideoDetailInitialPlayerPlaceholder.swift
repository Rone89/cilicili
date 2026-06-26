import SwiftUI

struct VideoDetailInitialPlayerPlaceholder: View {
    let width: CGFloat
    let height: CGFloat
    let showsPinnedProgressBar: Bool
    let onNavigateBack: () -> Void

    var body: some View {
        PlayerLoadingPlaceholder(
            progress: 0.08,
            message: "加载视频信息",
            isFinishing: false,
            showsChromeSkeleton: true
        )
        .frame(width: width, height: height)
        .background(VideoDetailInitialPlayerPlaceholderBackgroundLayer())
        .overlay(alignment: .topLeading) {
            VideoDetailInitialPlayerPlaceholderBackButtonLayer(action: onNavigateBack)
        }
        .overlay(alignment: .bottom) {
            if showsPinnedProgressBar {
                VideoDetailInitialPlayerPlaceholderProgressLayer(width: width)
            }
        }
    }
}
