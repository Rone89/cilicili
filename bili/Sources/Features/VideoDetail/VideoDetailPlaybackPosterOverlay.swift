import Combine
import SwiftUI

struct PlaybackPosterOverlay: View {
    let video: VideoItem
    let playerViewModel: PlayerStateViewModel
    let dimOpacity: Double
    let showsLoader: Bool
    @StateObject private var state = PlaybackPosterOverlayState()

    var body: some View {
        let snapshot = state.snapshot
        PlaybackPosterLoadingLayer(
            snapshot: snapshot,
            dimOpacity: dimOpacity
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .playbackPosterOverlayLifecycle(
            playerViewModel: playerViewModel,
            state: state
        )
    }
}

private struct PlaybackPosterLoadingLayer: View {
    let snapshot: PlaybackPosterSnapshot
    let dimOpacity: Double

    var body: some View {
        ZStack {
            if snapshot.shouldShowPoster {
                PlayerLoadingPlaceholder(
                    progress: snapshot.loadingProgress,
                    message: snapshot.loadingMessage,
                    isFinishing: snapshot.isFinishing,
                    showsChromeSkeleton: false
                )
                .background(Color.black.opacity(dimOpacity))
                .compositingGroup()
                .clipped()
                .transition(.opacity.animation(.easeOut(duration: 0.18)))
                .animation(.easeOut(duration: 0.18), value: snapshot.isPlaybackSurfaceReady)
            }
        }
    }
}
