import SwiftUI

struct BiliPlayerNativeControlsActionBuilder {
    let viewModel: PlayerStateViewModel
    let configuration: BiliPlayerViewConfiguration
    let visibilityActions: BiliPlayerPlaybackControlsVisibilityActions
    let prepareUserSeekWarmup: (Double, Bool) -> Void
    let resetPreparedScrubProgress: () -> Void

    var actions: PlayerNativePlaybackControlsActions {
        PlayerNativePlaybackControlsActions(
            onScrubStart: { _ in
                guard !viewModel.isTerminated else { return }
                visibilityActions.markInteraction(keepsVisible: true)
            },
            onScrubChanged: { _ in },
            onScrubEnded: { progress in
                guard !viewModel.isTerminated else {
                    resetPreparedScrubProgress()
                    return
                }
                prepareUserSeekWarmup(progress, true)
                viewModel.seekAfterUserScrub(to: progress)
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
