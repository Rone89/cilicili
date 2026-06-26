import SwiftUI

private struct VideoDetailPlaybackActivityBridgeModifier: ViewModifier {
    let playerViewModel: PlayerStateViewModel?
    @ObservedObject var playerIdentityStore: VideoDetailPlayerIdentityRenderStore
    let playbackActions: VideoDetailPinnedDynamicPlayerHeaderPlaybackActions

    func body(content: Content) -> some View {
        content.overlay {
            if let playerViewModel {
                let playerIdentity = ObjectIdentifier(playerViewModel)
                let playerIdentityRevision = playerIdentityStore.revision
                VideoDetailPlayerActivityBridge(playerViewModel: playerViewModel) { isActive in
                    guard playerIdentityStore.revision == playerIdentityRevision,
                          playerIdentityStore.playerViewModel.map(ObjectIdentifier.init) == playerIdentity
                    else { return }
                    playbackActions.updatePlaybackActive(isActive)
                }
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
            }
        }
        .onChange(of: playerIdentityStore.playerViewModel.map(ObjectIdentifier.init)) { _, identity in
            if identity == nil {
                playbackActions.updatePlaybackActive(false)
            }
        }
    }
}

extension View {
    func videoDetailPlaybackActivityBridge(
        playerViewModel: PlayerStateViewModel?,
        playerIdentityStore: VideoDetailPlayerIdentityRenderStore,
        playbackActions: VideoDetailPinnedDynamicPlayerHeaderPlaybackActions
    ) -> some View {
        modifier(
            VideoDetailPlaybackActivityBridgeModifier(
                playerViewModel: playerViewModel,
                playerIdentityStore: playerIdentityStore,
                playbackActions: playbackActions
            )
        )
    }
}
