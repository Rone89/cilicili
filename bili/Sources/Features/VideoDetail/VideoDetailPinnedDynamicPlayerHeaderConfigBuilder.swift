import SwiftUI

struct VideoDetailPinnedDynamicPlayerHeaderConfigBuilder {
    let screenSize: CGSize
    let standardHeight: CGFloat
    let isLandscape: Bool
    let usesFullscreenLayout: Bool
    let activeFullscreenMode: PlayerFullscreenMode?
    let targetFullscreenMode: PlayerFullscreenMode?
    let isCompletingFullscreenExit: Bool
    let isSystemRotationLayoutTransitioning: Bool
    let isDanmakuSettingsPresented: Bool
    let runtimeSettings: VideoDetailRuntimeSettingsSnapshot
    let actions: VideoDetailStandardPlaybackActions

    var config: VideoDetailPinnedDynamicPlayerHeaderConfig {
        VideoDetailPinnedDynamicPlayerHeaderConfig(
            screenSize: screenSize,
            playerWidth: playerWidth,
            playerHeight: playerHeight,
            isLandscape: isLandscape,
            isFullscreen: isFullscreen,
            fullscreenMode: activeFullscreenMode,
            targetFullscreenMode: targetFullscreenMode,
            isLayoutTransitioning: isLayoutTransitioning,
            suppressesPosterDuringFullscreenTransition: suppressesPosterDuringFullscreenTransition,
            isDanmakuSettingsPresented: isDanmakuSettingsPresented,
            showsPinnedProgressBar: runtimeSettings.showsPinnedProgressBar,
            onRequestFullscreen: actions.onRequestFullscreen,
            onExitFullscreen: exitHandler,
            onNavigateBack: actions.onNavigateBack,
            onShowDanmakuSettings: actions.onShowDanmakuSettings
        )
    }

    private var isFullscreen: Bool {
        activeFullscreenMode != nil
    }

    private var isLayoutTransitioning: Bool {
        isSystemRotationLayoutTransitioning || isCompletingFullscreenExit
    }

    private var suppressesPosterDuringFullscreenTransition: Bool {
        activeFullscreenMode != nil
            || isCompletingFullscreenExit
            || isSystemRotationLayoutTransitioning
    }

    private var playerHeight: CGFloat {
        guard !isFullscreen else { return screenSize.height }
        return standardHeight
    }

    private var playerWidth: CGFloat? {
        screenSize.width
    }

    private var exitHandler: (() -> Void)? {
        activeFullscreenMode == nil ? nil : actions.onExitFullscreen
    }
}
