import Foundation

struct VideoDetailPinnedPlayerContentActions {
    let selectPlayVariant: (PlayVariant) -> Void
    let onToggleDanmaku: () -> Void
    let onPrepareForUserSeek: (Double) -> Void
    let onDanmakuPlaybackTime: (TimeInterval, Bool) -> Void
    let onRequestFullscreen: (PlayerStateViewModel) -> Void
    let onExitFullscreen: (() -> Void)?
    let onNavigateBack: () -> Void
    let onShowDanmakuSettings: () -> Void

    init(
        headerConfig: VideoDetailPinnedDynamicPlayerHeaderConfig,
        selectPlayVariant: @escaping (PlayVariant) -> Void,
        onToggleDanmaku: @escaping () -> Void,
        onPrepareForUserSeek: @escaping (Double) -> Void,
        onDanmakuPlaybackTime: @escaping (TimeInterval, Bool) -> Void,
        onNavigateBack: @escaping () -> Void
    ) {
        self.selectPlayVariant = selectPlayVariant
        self.onToggleDanmaku = onToggleDanmaku
        self.onPrepareForUserSeek = onPrepareForUserSeek
        self.onDanmakuPlaybackTime = onDanmakuPlaybackTime
        onRequestFullscreen = headerConfig.onRequestFullscreen
        onExitFullscreen = headerConfig.onExitFullscreen
        self.onNavigateBack = onNavigateBack
        onShowDanmakuSettings = headerConfig.onShowDanmakuSettings
    }

    var surfaceActions: VideoDetailPlayerSurfaceActions {
        VideoDetailPlayerSurfaceActions(
            selectPlayVariant: selectPlayVariant,
            onToggleDanmaku: onToggleDanmaku,
            onPrepareForUserSeek: onPrepareForUserSeek,
            onDanmakuPlaybackTime: onDanmakuPlaybackTime,
            onRequestFullscreen: onRequestFullscreen,
            onExitFullscreen: onExitFullscreen,
            onNavigateBack: onNavigateBack,
            onShowDanmakuSettings: onShowDanmakuSettings
        )
    }

    func requestFullscreen(for playerViewModel: PlayerStateViewModel) {
        onRequestFullscreen(playerViewModel)
    }
}
