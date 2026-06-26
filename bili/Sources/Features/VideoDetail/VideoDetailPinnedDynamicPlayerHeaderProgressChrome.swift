import SwiftUI

struct VideoDetailPinnedDynamicPlayerHeaderProgressChrome: ViewModifier {
    @ObservedObject var playerIdentityStore: VideoDetailPlayerIdentityRenderStore
    let context: VideoDetailPinnedDynamicPlayerHeaderContext
    let onPrepareForUserSeek: (Double) -> Void

    func body(content: Content) -> some View {
        content.videoDetailPinnedProgressOverlay(
            configuration: context.progressOverlayConfiguration(
                playerViewModel: playerIdentityStore.playerViewModel,
                onPrepareSeek: onPrepareForUserSeek
            )
        )
    }
}
