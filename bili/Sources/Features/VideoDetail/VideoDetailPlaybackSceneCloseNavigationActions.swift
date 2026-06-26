import Foundation

@MainActor
struct VideoDetailPlaybackSceneCloseNavigationActions {
    let resetFullscreenForClose: () -> Void
    let stopPlaybackForNavigation: () -> Void
    let onNavigateBack: () -> Void

    func dismissVideoDetail(using state: VideoDetailPlaybackSceneCloseStateActions) {
        guard !state.isClosingDetail() else { return }
        state.markClosingDetail()
        resetFullscreenForClose()
        stopPlaybackForNavigation()
        onNavigateBack()
    }
}
