import SwiftUI

struct VideoDetailPinnedTransitionMaskOverlay: View {
    @ObservedObject var playerIdentityStore: VideoDetailPlayerIdentityRenderStore
    let playerWidth: CGFloat?
    let playerHeight: CGFloat

    private var isPresented: Bool {
        playerIdentityStore.transitionPlayerOpacity > 0
            && playerIdentityStore.transitionSnapshot != nil
    }

    var body: some View {
        if isPresented {
            VideoDetailPlayerTransitionMask(
                snapshot: playerIdentityStore.transitionSnapshot,
                fallbackCoverURL: playerIdentityStore.transitionFallbackCoverURL,
                playerWidth: playerWidth,
                playerHeight: playerHeight
            )
            .opacity(playerIdentityStore.transitionPlayerOpacity)
            .zIndex(2)
        }
    }
}
