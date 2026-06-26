import SwiftUI

struct LiveDanmakuOverlay: View {
    @ObservedObject var store: LiveDanmakuRenderStore
    @ObservedObject var playerViewModel: PlayerStateViewModel
    let usesLandscapeChrome: Bool

    var body: some View {
        let shouldDriveLiveDanmaku = playerViewModel.isPlaying || playerViewModel.wantsAutoplay

        DanmakuOverlayView(
            items: store.items,
            itemsRevision: store.itemsRevision,
            currentTime: store.playbackTime,
            isPlaying: shouldDriveLiveDanmaku,
            playbackRate: 1,
            isEnabled: store.isEnabled,
            hasPresentedPlayback: playerViewModel.hasPresentedPlayback || shouldDriveLiveDanmaku,
            settings: store.settings,
            topInset: usesLandscapeChrome ? 28 : 8,
            bottomInset: usesLandscapeChrome ? 84 : 54
        )
        .padding(.horizontal, usesLandscapeChrome ? 18 : 4)
    }
}
