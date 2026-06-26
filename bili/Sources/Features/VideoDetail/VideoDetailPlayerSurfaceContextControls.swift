import Foundation

struct VideoDetailPlayerSurfaceContextControls {
    let onToggleDanmaku: (() -> Void)?
    let onShowDanmakuSettings: (() -> Void)?
    let onPrepareForUserSeek: ((Double) -> Void)?
    let onRequestFullscreen: (() -> Void)?
    let onExitFullscreen: (() -> Void)?
}
