import SwiftUI

/// 播放器底部的字幕渲染层。时间驱动复用 PlayerPlaybackClock 的 0.2s 节流发布。
///
/// 位置与样式默认值对齐 PiliPlus：底部/水平 24pt、背景黑 67%、
/// 字号 16 ×（全屏 1.5 / 竖屏 1.0）；控制条可见时底部至少抬到 70pt 避免遮挡。
struct VideoDetailPlayerSurfaceSubtitleLayer: View {
    @ObservedObject var store: VideoDetailSubtitleStore
    @ObservedObject var controlsVisibility: PlayerPlaybackControlsVisibilityModel
    let clock: PlayerPlaybackClock
    let cid: Int?
    let isFullscreen: Bool
    let loadTracks: () async -> Void

    /// PiliPlus 默认值。
    private enum Layout {
        static let horizontalPadding: CGFloat = 24
        static let bottomPadding: CGFloat = 24
        /// 控制条出现时字幕的临时最低底部距离（PiliPlus 的 minPadding）。
        static let bottomPaddingWithControls: CGFloat = 70
        static let portraitFontSize: CGFloat = 16
        static let fullscreenFontScale: CGFloat = 1.5
        static let backgroundOpacity: Double = 0.67
    }

    private var fontSize: CGFloat {
        Layout.portraitFontSize * (isFullscreen ? Layout.fullscreenFontScale : 1)
    }

    private var bottomPadding: CGFloat {
        controlsVisibilityAreVisible
            ? max(Layout.bottomPadding, Layout.bottomPaddingWithControls)
            : Layout.bottomPadding
    }

    private var controlsVisibilityAreVisible: Bool {
        controlsVisibility.isVisible && controlsVisibility.opacity > 0.5
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            if let cue = store.currentCue {
                Text(cue.content.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Color.black.opacity(Layout.backgroundOpacity),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    .padding(.horizontal, Layout.horizontalPadding)
                    .shadow(color: .black.opacity(0.55), radius: 3, x: 0, y: 1)
                    .padding(.bottom, bottomPadding)
                    .animation(.easeOut(duration: 0.2), value: bottomPadding)
            } else if let message = store.loadErrorMessage {
                // 选轨失败/空内容时给出可见反馈，避免「选了但什么都不显示」。
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Color.black.opacity(Layout.backgroundOpacity),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    .padding(.bottom, bottomPadding)
            }
        }
        .allowsHitTesting(false)
        .onReceive(clock.$currentTime) { time in
            store.updateCurrentCue(at: time)
        }
        .task(id: cid) {
            await loadTracks()
        }
    }
}
