import SwiftUI

struct PlayerNativePlaybackControls: View {
    @ObservedObject var clock: PlayerPlaybackClock
    let metrics: PlayerNativeControlMetrics
    let canSeek: Bool
    let isPlaying: Bool
    let isDanmakuEnabled: Bool
    let showsDanmakuButton: Bool
    let canToggleFullscreen: Bool
    let isFullscreenActive: Bool
    let controlsAccessory: AnyView?
    let actions: PlayerNativePlaybackControlsActions

    var body: some View {
        GlassEffectContainer(spacing: metrics.groupSpacing) {
            VStack(spacing: metrics.stackSpacing) {
                PlayerNativeProgressSection(
                    metrics: metrics,
                    clock: clock,
                    canSeek: canSeek,
                    sliderVisualScale: metrics.sliderVisualScale,
                    onScrubStart: actions.onScrubStart,
                    onScrubChanged: actions.onScrubChanged,
                    onScrubEnded: actions.onScrubEnded
                )

                PlayerNativeControlButtonRow(
                    clock: clock,
                    metrics: metrics,
                    isPlaying: isPlaying,
                    isDanmakuEnabled: isDanmakuEnabled,
                    showsDanmakuButton: showsDanmakuButton,
                    canToggleFullscreen: canToggleFullscreen,
                    isFullscreenActive: isFullscreenActive,
                    controlsAccessory: controlsAccessory,
                    actions: actions
                )
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(.white)
        .controlSize(.mini)
    }
}
