import Foundation

struct VideoDetailPlayerSurfaceActions {
    let selectPlayVariant: (PlayVariant) -> Void
    let onToggleDanmaku: () -> Void
    let onPrepareForUserSeek: (Double) -> Void
    let onDanmakuPlaybackTime: (TimeInterval, Bool) -> Void
    let onRequestFullscreen: (PlayerStateViewModel) -> Void
    let onExitFullscreen: (() -> Void)?
    let onNavigateBack: () -> Void
    let onShowDanmakuSettings: () -> Void

    func requestFullscreen(for playerViewModel: PlayerStateViewModel) {
        onRequestFullscreen(playerViewModel)
    }
}
