import SwiftUI

@MainActor
struct VideoDetailPinnedDynamicPlayerHeaderContext {
    let config: VideoDetailPinnedDynamicPlayerHeaderConfig
    let renderState: VideoDetailPinnedDynamicPlayerHeaderRenderState
    let navigationActions: VideoDetailPinnedDynamicPlayerHeaderNavigationActions
    let playbackActions: VideoDetailPinnedDynamicPlayerHeaderPlaybackActions

    init(
        config: VideoDetailPinnedDynamicPlayerHeaderConfig,
        layout: VideoDetailPinnedDynamicPlayerHeaderLayout,
        scrollOffset: CGFloat,
        isPlaybackActive: Binding<Bool>
    ) {
        self.config = config
        renderState = VideoDetailPinnedDynamicPlayerHeaderRenderState(
            config: config,
            layout: layout,
            scrollOffset: scrollOffset,
            isPlaybackActive: isPlaybackActive.wrappedValue
        )
        navigationActions = VideoDetailPinnedDynamicPlayerHeaderNavigationActions(
            onExitFullscreen: config.onExitFullscreen,
            onNavigateBack: config.onNavigateBack
        )
        playbackActions = VideoDetailPinnedDynamicPlayerHeaderPlaybackActions(
            isPlaybackActive: isPlaybackActive
        )
    }

    func progressOverlayConfiguration(
        playerViewModel: PlayerStateViewModel?,
        onPrepareSeek: @escaping (Double) -> Void
    ) -> VideoDetailPinnedProgressOverlayConfiguration {
        renderState.progressOverlayConfiguration(
            config: config,
            playerViewModel: playerViewModel,
            onPrepareSeek: onPrepareSeek
        )
    }
}
