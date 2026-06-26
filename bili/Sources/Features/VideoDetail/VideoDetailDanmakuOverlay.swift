import SwiftUI

struct VideoDetailDanmakuOverlay: View {
    let store: VideoDetailDanmakuRenderStore
    let playerViewModel: PlayerStateViewModel
    let clock: PlayerPlaybackClock
    let usesLandscapePlaybackChrome: Bool
    let onPlaybackTime: (TimeInterval, Bool) -> Void
    @StateObject private var state = VideoDetailDanmakuOverlayState()

    var body: some View {
        let snapshot = state.snapshot

        DanmakuOverlayView(
            items: snapshot.items,
            itemsRevision: snapshot.itemsRevision,
            isPlaying: snapshot.isPlaying,
            playbackRate: snapshot.playbackRate,
            isEnabled: snapshot.isEnabled,
            hasPresentedPlayback: snapshot.hasPresentedPlayback,
            isLoadShedding: snapshot.isLoadShedding,
            settings: snapshot.settings,
            topInset: usesLandscapePlaybackChrome ? 28 : 8,
            bottomInset: usesLandscapePlaybackChrome ? 84 : 54,
            playbackClock: clock,
            onPlaybackTime: onPlaybackTime
        )
        .padding(.horizontal, usesLandscapePlaybackChrome ? 0 : 4)
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
