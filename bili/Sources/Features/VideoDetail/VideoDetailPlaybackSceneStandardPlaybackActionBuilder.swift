import Foundation

@MainActor
struct VideoDetailPlaybackSceneStandardPlaybackActionBuilder {
    let fullscreenActions: VideoDetailPlaybackSceneFullscreenActions
    let closeActions: VideoDetailPlaybackSceneCloseActions
    let sheetActions: VideoDetailPlaybackSceneSheetActions

    var actions: VideoDetailStandardPlaybackActions {
        VideoDetailStandardPlaybackActions(
            onRequestFullscreen: fullscreenActions.presentation.requestManualFullscreen,
            onExitFullscreen: fullscreenActions.presentation.exitFullscreenPlayback,
            onNavigateBack: dismissVideoDetail,
            onShowDanmakuSettings: sheetActions.settings.showDanmakuSettings,
            onShowNetworkDiagnostics: sheetActions.settings.showNetworkDiagnostics,
            onShowFavoriteFolders: sheetActions.settings.showFavoriteFolders,
            onReply: sheetActions.reply.showReplySheet
        )
    }

    private func dismissVideoDetail() {
        closeActions.dismissVideoDetail()
    }
}
