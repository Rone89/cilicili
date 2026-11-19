import SwiftUI

struct VideoDetailDanmakuOverlay: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    let store: VideoDetailDanmakuRenderStore
    let playerViewModel: PlayerStateViewModel
    let clock: PlayerPlaybackClock
    let usesLandscapePlaybackChrome: Bool
    let logicalCanvasSize: CGSize?
    let videoAspectRatio: CGFloat?
    var additionalTopInset: CGFloat = 0
    var additionalBottomInset: CGFloat = 0
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
            // 横屏全屏：顶部不再预留，弹幕可顶到最上沿（100% 时铺满除底部
            // 控件区以外的区域）；底部仍为进度条/控件让位。
            topInset: (usesLandscapePlaybackChrome ? 0 : 8) + max(0, additionalTopInset),
            bottomInset: (usesLandscapePlaybackChrome ? 84 : 54) + max(0, additionalBottomInset),
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

    /// 弹幕渲染后端选择：点播默认走系统媒体时钟同步层（`AVSynchronizedLayer`），
    /// 直播或无 AVPlayer 场景自动回退到 Metal。
    private var danmakuRendererPreference: DanmakuRendererPreference {
        if PlaybackDiagnosticsExperiment.forceMetalDanmaku { return .metal }
        return playerViewModel.danmakuSyncPlayer != nil ? .synchronizedLayer : .metal
    }
}
