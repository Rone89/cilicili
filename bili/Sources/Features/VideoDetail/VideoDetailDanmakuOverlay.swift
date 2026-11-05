import SwiftUI

struct VideoDetailDanmakuOverlay: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    let store: VideoDetailDanmakuRenderStore
    let playerViewModel: PlayerStateViewModel
    let clock: PlayerPlaybackClock
    let usesLandscapePlaybackChrome: Bool
    let logicalCanvasSize: CGSize?
    let videoAspectRatio: CGFloat?
    let isLayoutTransitioning: Bool
    let onPlaybackTime: (TimeInterval, Bool) -> Void
    @StateObject private var state = VideoDetailDanmakuOverlayState()

    var body: some View {
        let snapshot = state.snapshot
        let isVisibleInCurrentOrientation = usesLandscapePlaybackChrome || !snapshot.settings.hidesInPortrait

        DanmakuOverlayView(
            items: snapshot.items,
            itemsRevision: snapshot.itemsRevision,
            currentTime: clock.currentTime,
            isPlaying: snapshot.isPlaying,
            playbackRate: snapshot.playbackRate,
            isEnabled: snapshot.isEnabled && isVisibleInCurrentOrientation,
            hasPresentedPlayback: snapshot.hasPresentedPlayback,
            isLoadShedding: snapshot.isLoadShedding
                || PlaybackDiagnosticsExperiment.forceDanmakuLoadShedding,
            settings: snapshot.settings,
            topInset: usesLandscapePlaybackChrome ? 28 : 8,
            bottomInset: usesLandscapePlaybackChrome ? 84 : 54,
            isLayoutTransitioning: isLayoutTransitioning,
            playbackClock: clock,
            onPlaybackTime: onPlaybackTime,
            // Metal 弹幕在 4K HDR（EDR 合成）下与视频解码/合成争抢 GPU，实测会导致
            // 播放页 UI 严重掉帧（fps 2–27、最长卡顿 2s+）。HDR 播放回退到 DanmakuKit。
            // 弹幕渲染器与 HDR 无关（已用自动自测验证两种渲染器在 HDR 下均流畅），
            // 遵循用户的 Metal 弹幕实验开关。
            metalRendererEnabled: PlaybackDiagnosticsExperiment.forceDanmakuKit
                ? false
                : (PlaybackDiagnosticsExperiment.forceMetalDanmaku
                    || libraryStore.metalDanmakuRendererExperimentEnabled),
            logicalCanvasSize: logicalCanvasSize,
            videoAspectRatio: videoAspectRatio
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onAppear {
            PlaybackHitchMonitor.shared.updateDanmakuContext(
                itemCount: snapshot.items.count,
                isEnabled: snapshot.isEnabled
            )
        }
        .onChange(of: snapshot.itemsRevision) { _, _ in
            PlaybackHitchMonitor.shared.updateDanmakuContext(
                itemCount: snapshot.items.count,
                isEnabled: snapshot.isEnabled
            )
        }
        .onChange(of: snapshot.isEnabled) { _, enabled in
            PlaybackHitchMonitor.shared.updateDanmakuContext(
                itemCount: snapshot.items.count,
                isEnabled: enabled
            )
        }
        .videoDetailDanmakuOverlayLifecycle(
            store: store,
            playerViewModel: playerViewModel,
            clock: clock,
            isEnabled: snapshot.isEnabled,
            state: state,
            onPlaybackTime: onPlaybackTime
        )
    }
}
