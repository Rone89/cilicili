import SwiftUI

struct VideoDetailStandardPlaybackPageLifecycleActions {
    @Binding var scrollState: VideoDetailStandardPlaybackScrollState

    func handleFullscreenChanged(_ isFullscreen: Bool) {
        guard isFullscreen else { return }
        scrollState.reset()
    }
}
