import SwiftUI

/// 播放器底部的字幕渲染层。时间驱动复用 PlayerPlaybackClock 的 0.2s 节流发布。
struct VideoDetailPlayerSurfaceSubtitleLayer: View {
    @ObservedObject var store: VideoDetailSubtitleStore
    let clock: PlayerPlaybackClock
    let cid: Int?
    let loadTracks: () async -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            if let cue = store.currentCue {
                Text(cue.content.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(.horizontal, 16)
                    .shadow(color: .black.opacity(0.55), radius: 3, x: 0, y: 1)
                    .padding(.bottom, 22)
            } else if let message = store.loadErrorMessage {
                // 选轨失败/空内容时给出可见反馈，避免「选了但什么都不显示」。
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(.bottom, 22)
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
