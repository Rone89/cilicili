import SwiftUI

struct BiliPlayerNativeControlsHost: View {
    let context: BiliPlayerViewRenderContext
    let renderState: BiliPlayerViewRenderState

    var body: some View {
        PlayerNativePlaybackControls(
            clock: context.viewModel.playbackClock,
            metrics: renderState.controlMetrics,
            canSeek: context.surfaceState.canSeek,
            isPlaying: context.surfaceState.isPlaying,
            isDanmakuEnabled: context.configuration.isDanmakuEnabled,
            showsDanmakuButton: false,
            canToggleFullscreen: context.configuration.canToggleFullscreen,
            isFullscreenActive: context.configuration.isFullscreenActive,
            controlsAccessory: context.configuration.controlsAccessory,
            actions: nativePlaybackControlsActions
        )
    }

    private var nativePlaybackControlsActions: PlayerNativePlaybackControlsActions {
        BiliPlayerNativeControlsActionBuilder(
            viewModel: context.viewModel,
            configuration: context.configuration,
            visibilityActions: renderState.visibilityActions,
            prepareUserSeekWarmup: context.prepareUserSeekWarmup,
            resetPreparedScrubProgress: context.resetPreparedScrubProgress
        ).actions
    }
}
