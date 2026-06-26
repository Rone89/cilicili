import Foundation

struct VideoDetailPlayerSurfaceContextControlsBuilder {
    let playerViewModel: PlayerStateViewModel
    let actions: VideoDetailPlayerSurfaceActions

    var controls: VideoDetailPlayerSurfaceContextControls {
        VideoDetailPlayerSurfaceContextControls(
            onToggleDanmaku: actions.onToggleDanmaku,
            onShowDanmakuSettings: actions.onShowDanmakuSettings,
            onPrepareForUserSeek: actions.onPrepareForUserSeek,
            onRequestFullscreen: requestFullscreen,
            onExitFullscreen: actions.onExitFullscreen
        )
    }

    private func requestFullscreen() {
        actions.requestFullscreen(for: playerViewModel)
    }
}
