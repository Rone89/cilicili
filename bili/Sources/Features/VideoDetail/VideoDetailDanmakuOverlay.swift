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
        let rendererPreference = danmakuRendererPreference

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
            rendererPreference: rendererPreference,
            syncPlayer: playerViewModel.danmakuSyncPlayer,
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

    /// 弹幕渲染后端选择。优先级：诊断强制 > 同步层实验（需引擎暴露 AVPlayer，
    /// 直播等无播放器场景自动回退）> Metal 实验 > DanmakuKit。
    /// Metal 弹幕与 HDR 无关（已用自动自测验证两种渲染器在 4K HDR 下均流畅），
    /// 遵循用户的 Metal 弹幕实验开关。
    private var danmakuRendererPreference: DanmakuRendererPreference {
        if PlaybackDiagnosticsExperiment.forceDanmakuKit { return .danmakuKit }
        if PlaybackDiagnosticsExperiment.forceMetalDanmaku { return .metal }
        if libraryStore.danmakuSynchronizedLayerRendererEnabled,
           playerViewModel.danmakuSyncPlayer != nil {
            return .synchronizedLayer
        }
        return libraryStore.metalDanmakuRendererExperimentEnabled ? .metal : .danmakuKit
    }
}
