import Foundation

@MainActor
struct VideoDetailPlaybackSceneSheetActionBuilder {
    let callbacks: VideoDetailPlaybackSceneSheetCallbacks

    var actions: VideoDetailPlaybackSceneSheetActions {
        VideoDetailPlaybackSceneSheetActions(
            settings: settingsActions,
            reply: replyActions
        )
    }

    private var settingsActions: VideoDetailPlaybackSceneSettingsSheetActions {
        VideoDetailPlaybackSceneSettingsSheetActions(
            showDanmakuSettings: callbacks.showDanmakuSettings,
            showNetworkDiagnostics: callbacks.showNetworkDiagnostics,
            showFavoriteFolders: callbacks.showFavoriteFolders
        )
    }

    private var replyActions: VideoDetailPlaybackSceneReplySheetActions {
        VideoDetailPlaybackSceneReplySheetActions(
            showReplySheet: callbacks.showReplySheet
        )
    }
}
