import SwiftUI

struct VideoDetailPlaybackSceneLayerAnimations: ViewModifier {
    @ObservedObject var fullscreenCoordinator: VideoDetailFullscreenCoordinator
    let layout: VideoDetailPlaybackSceneLayout

    func body(content: Content) -> some View {
        content
            .animation(
                fullscreenCoordinator.isSystemRotationLayoutTransitioning
                    ? nil
                    : VideoDetailFullscreenCoordinator.inlineTransitionAnimation,
                value: fullscreenCoordinator.mode
            )
            .animation(
                fullscreenCoordinator.isSystemRotationLayoutTransitioning
                    ? nil
                    : VideoDetailFullscreenCoordinator.inlineTransitionAnimation,
                value: layout.effectiveFullscreenMode
            )
    }
}

extension View {
    func videoDetailPlaybackSceneLayerAnimations(
        fullscreenCoordinator: VideoDetailFullscreenCoordinator,
        layout: VideoDetailPlaybackSceneLayout
    ) -> some View {
        modifier(
            VideoDetailPlaybackSceneLayerAnimations(
                fullscreenCoordinator: fullscreenCoordinator,
                layout: layout
            )
        )
    }
}
