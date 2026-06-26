import SwiftUI

struct PlayerNativeControlButtonRow: View {
    @ObservedObject var clock: PlayerPlaybackClock
    let metrics: PlayerNativeControlMetrics
    let isPlaying: Bool
    let isDanmakuEnabled: Bool
    let showsDanmakuButton: Bool
    let canToggleFullscreen: Bool
    let isFullscreenActive: Bool
    let controlsAccessory: AnyView?
    let actions: PlayerNativePlaybackControlsActions

    var body: some View {
        HStack(spacing: metrics.controlSpacing) {
            PlayerNativeGlassIconButton(
                systemName: isPlaying ? "pause.fill" : "play.fill",
                accessibilityLabel: isPlaying ? "暂停" : "播放",
                metrics: metrics,
                action: actions.onTogglePlayback
            )

            PlayerNativeTimeLabel(clock: clock, metrics: metrics)
                .frame(
                    width: metrics.timeLabelWidth,
                    height: metrics.controlHeight
                )
                .biliPlayerClearGlass(interactive: false, in: Capsule())

            Spacer(minLength: 0)

            if let controlsAccessory {
                controlsAccessory
                    .frame(height: metrics.controlHeight)
            }

            if showsDanmakuButton {
                PlayerNativeGlassIconButton(
                    systemName: isDanmakuEnabled ? "text.bubble.fill" : "text.bubble",
                    accessibilityLabel: "弹幕设置",
                    metrics: metrics,
                    action: actions.onToggleDanmaku
                )
            }

            if canToggleFullscreen {
                PlayerNativeGlassIconButton(
                    systemName: isFullscreenActive ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                    accessibilityLabel: isFullscreenActive ? "退出全屏" : "全屏",
                    metrics: metrics,
                    action: actions.onToggleFullscreen
                )
            }
        }
        .frame(height: metrics.controlHeight)
    }
}
