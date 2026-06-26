import SwiftUI

struct VideoDetailPinnedDynamicPlayerHeaderLayoutChrome: ViewModifier {
    let playerWidth: CGFloat?
    let renderState: VideoDetailPinnedDynamicPlayerHeaderRenderState
    let isLayoutTransitioning: Bool

    func body(content: Content) -> some View {
        content
            .frame(width: playerWidth)
            .frame(maxWidth: .infinity)
            .frame(height: renderState.playerHeight)
            .clipped()
            .zIndex(1)
            .animation(nil, value: renderState.playerHeight)
    }
}
