import SwiftUI

struct VideoDetailDanmakuOverlay: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    let store: VideoDetailDanmakuRenderStore
    let playerViewModel: PlayerStateViewModel
    let clock: PlayerPlaybackClock
    let usesLandscapePlaybackChrome: Bool
    let logicalCanvasSize: CGSize?
    let isLayoutTransitioning: Bool
    let onPlaybackTime: (TimeInterval, Bool) -> Void
    @StateObject private var state = VideoDetailDanmakuOverlayState()

    var body: some View {
        let snapshot = state.snapshot
        let horizontalInset: CGFloat = usesLandscapePlaybackChrome ? 0 : 4
        let isVisibleInCurrentOrientation = usesLandscapePlaybackChrome || !snapshot.settings.hidesInPortrait

        DanmakuOverlayView(
            items: snapshot.items,
            itemsRevision: snapshot.itemsRevision,
            currentTime: clock.currentTime,
            isPlaying: snapshot.isPlaying,
            playbackRate: snapshot.playbackRate,
            isEnabled: snapshot.isEnabled && isVisibleInCurrentOrientation,
            hasPresentedPlayback: snapshot.hasPresentedPlayback,
            isLoadShedding: snapshot.isLoadShedding,
            settings: snapshot.settings,
            topInset: usesLandscapePlaybackChrome ? 28 : 8,
            bottomInset: usesLandscapePlaybackChrome ? 84 : 54,
            isLayoutTransitioning: isLayoutTransitioning,
            playbackClock: clock,
            onPlaybackTime: onPlaybackTime,
            metalRendererEnabled: libraryStore.metalDanmakuRendererExperimentEnabled,
            logicalCanvasSize: logicalCanvasSize.map {
                CGSize(width: max(0, $0.width - 2 * horizontalInset), height: $0.height)
            }
        )
        .padding(.horizontal, horizontalInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
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
