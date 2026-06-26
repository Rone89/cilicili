import SwiftUI

struct VideoDetailStandardPlaybackActions {
    let onRequestFullscreen: (PlayerStateViewModel) -> Void
    let onExitFullscreen: () -> Void
    let onNavigateBack: () -> Void
    let onShowDanmakuSettings: () -> Void
    let onShowNetworkDiagnostics: () -> Void
    let onShowFavoriteFolders: () -> Void
    let onReply: (Comment) -> Void
}

typealias VideoDetailStandardPlaybackConfigurationBuilder = VideoDetailStandardPlaybackPageConfigBuilder
