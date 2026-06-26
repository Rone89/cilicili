import Foundation

@MainActor
struct VideoDetailPlaybackSceneSettingsSheetActions {
    let showDanmakuSettings: () -> Void
    let showNetworkDiagnostics: () -> Void
    let showFavoriteFolders: () -> Void
}
