import SwiftUI

struct VideoDetailPinnedCollapsedChromeOverlay: View {
    @ObservedObject var playerViewModel: PlayerStateViewModel
    let isPresented: Bool
    let onNavigateBack: () -> Void
    let onRequestFullscreen: () -> Void

    var body: some View {
        if isPresented {
            VideoDetailCollapsedPlayerBar(
                playerViewModel: playerViewModel,
                onNavigateBack: onNavigateBack,
                onRequestFullscreen: onRequestFullscreen
            )
            .transition(.opacity)
            .zIndex(3)
        }
    }
}
