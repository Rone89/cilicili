import SwiftUI
import UIKit

struct VideoDetailInitialPlaybackStage: View {
    let seedVideo: VideoItem
    let layout: VideoDetailInitialPlaybackLayout
    let containerHeight: CGFloat
    @Binding var selectedContentTab: VideoDetailContentTab
    let runtimeSettings: VideoDetailRuntimeSettingsSnapshot
    let onNavigateBack: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            VideoDetailTheme.background
                .ignoresSafeArea()

            VideoDetailNativeContentTabView(
                selection: $selectedContentTab,
                layoutWidth: layout.width,
                topInset: layout.playerHeight,
                minimizesTabBarOnScroll: runtimeSettings.minimizesTabBarOnScroll,
                onScrollOffsetChange: { _, _ in }
            ) { tab in
                InitialVideoDetailContentPage(
                    seedVideo: seedVideo,
                    layoutWidth: layout.width,
                    tab: tab
                )
            }
            .frame(width: layout.width, height: containerHeight)

            VideoDetailInitialPlayerPlaceholder(
                width: layout.width,
                height: layout.playerHeight,
                showsPinnedProgressBar: runtimeSettings.showsPinnedProgressBar,
                onNavigateBack: onNavigateBack
            )
            .zIndex(1)

            VideoDetailStatusBarBackdrop(isHidden: false)
        }
        .frame(width: layout.width, height: containerHeight)
        .background(VideoDetailTheme.background)
        .background {
            StatusBarStyleBridge(
                style: .lightContent,
                isHidden: false
            )
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
        }
    }
}
