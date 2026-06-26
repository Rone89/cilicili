import SwiftUI

private struct VideoDetailStandardPlaybackPageLifecycleModifier: ViewModifier {
    let isFullscreen: Bool
    let actions: VideoDetailStandardPlaybackPageLifecycleActions

    func body(content: Content) -> some View {
        content
            .onChange(of: isFullscreen) { _, isFullscreen in
                actions.handleFullscreenChanged(isFullscreen)
            }
    }
}

extension View {
    func videoDetailStandardPlaybackPageLifecycle(
        isFullscreen: Bool,
        scrollState: Binding<VideoDetailStandardPlaybackScrollState>
    ) -> some View {
        modifier(
            VideoDetailStandardPlaybackPageLifecycleModifier(
                isFullscreen: isFullscreen,
                actions: VideoDetailStandardPlaybackPageLifecycleActions(scrollState: scrollState)
            )
        )
    }
}
