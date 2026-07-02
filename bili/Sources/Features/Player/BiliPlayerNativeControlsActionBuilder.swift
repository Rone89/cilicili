import SwiftUI

struct BiliPlayerNativeControlsActionBuilder {
    let viewModel: PlayerStateViewModel
    let configuration: BiliPlayerViewConfiguration
    let visibilityActions: BiliPlayerPlaybackControlsVisibilityActions
    let holdCurrentFrameForSeek: () -> Void
    let prepareUserSeekWarmup: (Double, Bool) -> Void
    let resetPreparedScrubProgress: () -> Void

    var actions: PlayerNativePlaybackControlsActions {
        PlayerNativePlaybackControlsActions(
            onScrubStart: { progress in
                guard !viewModel.isTerminated else { return }
                visibilityActions.markInteraction(keepsVisible: true)
                prepareUserSeekWarmup(progress, true)
                viewModel.beginUserScrubInteraction()
            },
            onScrubChanged: { progress in
                guard !viewModel.isTerminated else { return }
                prepareUserSeekWarmup(progress, false)
            },
            onScrubEnded: { progress in
                guard !viewModel.isTerminated else {
                    resetPreparedScrubProgress()
                    return
                }
                prepareUserSeekWarmup(progress, true)
                holdCurrentFrameForSeek()
                viewModel.seekAfterSliderCommit(to: progress)
                resetPreparedScrubProgress()
                visibilityActions.markInteraction()
            },
            onTogglePlayback: {
                guard !viewModel.isTerminated else { return }
                visibilityActions.markInteraction()
                viewModel.togglePlayback()
            },
            onToggleDanmaku: {
                guard !viewModel.isTerminated else { return }
                if let onShowDanmakuSettings = configuration.onShowDanmakuSettings {
                    visibilityActions.markInteraction(keepsVisible: true)
                    onShowDanmakuSettings()
                } else {
                    visibilityActions.markInteraction()
                    configuration.onToggleDanmaku?()
                }
            },
            onToggleFullscreen: {
                guard !viewModel.isTerminated else { return }
                visibilityActions.markInteraction()
                if configuration.isFullscreenActive {
                    configuration.onExitFullscreen?()
                } else {
                    configuration.onRequestFullscreen?()
                }
            }
        )
    }
}
