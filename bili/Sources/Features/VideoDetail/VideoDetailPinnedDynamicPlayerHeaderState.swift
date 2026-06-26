import SwiftUI

struct VideoDetailPinnedDynamicPlayerHeaderRenderState {
    let playerHeight: CGFloat
    let usesCollapsedChrome: Bool

    init(
        config: VideoDetailPinnedDynamicPlayerHeaderConfig,
        layout: VideoDetailPinnedDynamicPlayerHeaderLayout,
        scrollOffset: CGFloat,
        isPlaybackActive: Bool
    ) {
        let activeHeight = Self.activePlayerHeight(
            config: config,
            layout: layout,
            scrollOffset: scrollOffset,
            isPlaybackActive: isPlaybackActive
        )
        playerHeight = activeHeight
        usesCollapsedChrome = layout.usesCollapsedChrome(
            playerHeight: activeHeight,
            isPlaybackActive: isPlaybackActive
        )
    }

    func progressOverlayConfiguration(
        config: VideoDetailPinnedDynamicPlayerHeaderConfig,
        playerViewModel: PlayerStateViewModel?,
        onPrepareSeek: @escaping (Double) -> Void
    ) -> VideoDetailPinnedProgressOverlayConfiguration {
        VideoDetailPinnedProgressOverlayConfiguration(
            isPresented: config.showsPinnedProgressBar
                && !usesCollapsedChrome
                && !config.isLandscape
                && config.fullscreenMode == nil,
            playerWidth: config.playerWidth,
            playerViewModel: playerViewModel,
            onPrepareSeek: onPrepareSeek
        )
    }

    private static func activePlayerHeight(
        config: VideoDetailPinnedDynamicPlayerHeaderConfig,
        layout: VideoDetailPinnedDynamicPlayerHeaderLayout,
        scrollOffset: CGFloat,
        isPlaybackActive: Bool
    ) -> CGFloat {
        if config.isFullscreen || config.isLandscape {
            return config.playerHeight
        }
        return layout.playerHeight(
            fallbackHeight: config.playerHeight,
            scrollOffset: scrollOffset,
            isPlaybackActive: isPlaybackActive
        )
    }
}
