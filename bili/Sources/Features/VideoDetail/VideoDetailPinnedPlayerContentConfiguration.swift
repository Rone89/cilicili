import SwiftUI

struct VideoDetailPinnedPlayerContentConfiguration {
    let playerWidth: CGFloat?
    let playerHeight: CGFloat
    let isLandscape: Bool
    let fullscreenMode: PlayerFullscreenMode?
    let isLayoutTransitioning: Bool
    let suppressesPosterDuringFullscreenTransition: Bool
    let isDanmakuSettingsPresented: Bool
    let usesCollapsedChrome: Bool

    init(
        headerConfig: VideoDetailPinnedDynamicPlayerHeaderConfig,
        playerHeight: CGFloat,
        usesCollapsedChrome: Bool
    ) {
        playerWidth = headerConfig.playerWidth
        self.playerHeight = playerHeight
        isLandscape = headerConfig.isLandscape
        fullscreenMode = headerConfig.fullscreenMode
        isLayoutTransitioning = headerConfig.isLayoutTransitioning
        suppressesPosterDuringFullscreenTransition = headerConfig.suppressesPosterDuringFullscreenTransition
        isDanmakuSettingsPresented = headerConfig.isDanmakuSettingsPresented
        self.usesCollapsedChrome = usesCollapsedChrome
    }

    var surfaceConfiguration: VideoDetailPlayerSurfaceConfiguration {
        VideoDetailPlayerSurfaceConfiguration(
            isLandscape: isLandscape,
            playerWidth: playerWidth,
            playerHeight: playerHeight,
            fullscreenMode: fullscreenMode,
            isLayoutTransitioning: isLayoutTransitioning,
            suppressesPosterDuringFullscreenTransition: suppressesPosterDuringFullscreenTransition,
            isDanmakuSettingsPresented: isDanmakuSettingsPresented,
            showsPlaybackControls: !usesCollapsedChrome
        )
    }
}
