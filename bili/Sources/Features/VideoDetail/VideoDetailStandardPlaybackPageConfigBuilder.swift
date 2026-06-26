import SwiftUI

struct VideoDetailStandardPlaybackPageConfigBuilder {
    let screenSize: CGSize
    let isLandscape: Bool
    let usesFullscreenLayout: Bool
    let activeFullscreenMode: PlayerFullscreenMode?
    let targetFullscreenMode: PlayerFullscreenMode?
    let isCompletingFullscreenExit: Bool
    let isSystemRotationLayoutTransitioning: Bool
    let isDanmakuSettingsPresented: Bool
    let runtimeSettings: VideoDetailRuntimeSettingsSnapshot
    let actions: VideoDetailStandardPlaybackActions

    var pageConfig: VideoDetailStandardPlaybackPageConfig {
        VideoDetailStandardPlaybackPageConfig(
            screenSize: screenSize,
            standardHeight: standardHeight,
            isLandscape: isLandscape,
            isFullscreen: isFullscreen,
            isLayoutTransitioning: isLayoutTransitioning,
            minimizesTabBarOnScroll: runtimeSettings.minimizesTabBarOnScroll,
            headerConfig: headerConfig
        )
    }

    private var standardHeight: CGFloat {
        screenSize.width * 9 / 16
    }

    private var isFullscreen: Bool {
        activeFullscreenMode != nil
    }

    private var isLayoutTransitioning: Bool {
        isSystemRotationLayoutTransitioning || isCompletingFullscreenExit
    }

    private var headerConfig: VideoDetailPinnedDynamicPlayerHeaderConfig {
        VideoDetailPinnedDynamicPlayerHeaderConfigBuilder(
            screenSize: screenSize,
            standardHeight: standardHeight,
            isLandscape: isLandscape,
            usesFullscreenLayout: usesFullscreenLayout,
            activeFullscreenMode: activeFullscreenMode,
            targetFullscreenMode: targetFullscreenMode,
            isCompletingFullscreenExit: isCompletingFullscreenExit,
            isSystemRotationLayoutTransitioning: isSystemRotationLayoutTransitioning,
            isDanmakuSettingsPresented: isDanmakuSettingsPresented,
            runtimeSettings: runtimeSettings,
            actions: actions
        ).config
    }
}
