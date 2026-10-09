import SwiftUI

struct VideoDetailInitialPlayerPlaceholder: View {
    let width: CGFloat
    let height: CGFloat
    let showsPinnedProgressBar: Bool

    var body: some View {
        PlaybackDetailPlayerSurface(width: width, height: height) {
            PlayerLoadingPlaceholder(
                progress: 0.08,
                message: "加载视频信息",
                isFinishing: false,
                showsChromeSkeleton: true,
                showsProgress: false
            )
            .overlay(alignment: .bottom) {
                if showsPinnedProgressBar {
                    VideoDetailInitialPlayerPlaceholderProgressLayer(width: width)
                }
            }
        }
    }
}
