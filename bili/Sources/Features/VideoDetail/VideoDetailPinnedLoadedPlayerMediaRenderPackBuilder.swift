import Foundation

struct VideoDetailPinnedLoadedPlayerMediaRenderPackBuilder {
    let config: VideoDetailPinnedDynamicPlayerHeaderConfig
    let playerHeight: CGFloat
    let usesCollapsedChrome: Bool
    let selectPlayVariant: (PlayVariant) -> Void
    let onToggleDanmaku: () -> Void
    let onPrepareForUserSeek: (Double) -> Void
    let onDanmakuPlaybackTime: (TimeInterval, Bool) -> Void
    let onNavigateBack: () -> Void

    var renderPack: VideoDetailPinnedLoadedPlayerMediaRenderPack {
        VideoDetailPinnedLoadedPlayerMediaRenderPack(
            configuration: configuration,
            actions: actions
        )
    }

    private var configuration: VideoDetailPinnedPlayerContentConfiguration {
        VideoDetailPinnedPlayerContentConfiguration(
            headerConfig: config,
            playerHeight: playerHeight,
            usesCollapsedChrome: usesCollapsedChrome
        )
    }

    private var actions: VideoDetailPinnedPlayerContentActions {
        VideoDetailPinnedPlayerContentActions(
            headerConfig: config,
            selectPlayVariant: selectPlayVariant,
            onToggleDanmaku: onToggleDanmaku,
            onPrepareForUserSeek: onPrepareForUserSeek,
            onDanmakuPlaybackTime: onDanmakuPlaybackTime,
            onNavigateBack: onNavigateBack
        )
    }
}
