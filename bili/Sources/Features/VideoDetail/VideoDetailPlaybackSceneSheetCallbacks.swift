import Foundation

@MainActor
struct VideoDetailPlaybackSceneSheetCallbacks {
    let showDanmakuSettings: () -> Void
    let showNetworkDiagnostics: () -> Void
    let showFavoriteFolders: () -> Void
    let showReplySheet: (Comment) -> Void
}
