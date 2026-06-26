import SwiftUI

struct VideoDetailPinnedPlaceholderPlayerMedia: View {
    let config: VideoDetailPinnedDynamicPlayerHeaderConfig
    let playerHeight: CGFloat
    let stores: VideoDetailPinnedDynamicPlayerHeaderStores
    let onNavigateBack: () -> Void

    var body: some View {
        VideoDetailPlayerPlaceholder(
            placeholderStore: stores.placeholderStore,
            relatedStore: stores.relatedStore,
            playerWidth: config.playerWidth,
            playerHeight: playerHeight
        )
        .overlay(alignment: .topLeading) {
            VideoDetailPlayerBackButton(action: onNavigateBack)
                .padding(.top, 10)
                .padding(.leading, 10)
        }
    }
}
