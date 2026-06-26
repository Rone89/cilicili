import SwiftUI

struct VideoDetailStandardPlaybackContainerConfigBuilder {
    let layout: VideoDetailPlaybackSceneLayout
    let fullscreenCoordinator: VideoDetailFullscreenCoordinator
    let isShowingDanmakuSettings: Bool
    let runtimeSettings: VideoDetailRuntimeSettingsStore

    var config: VideoDetailStandardPlaybackContainerConfig {
        VideoDetailStandardPlaybackContainerConfig(
            screenSize: layout.playbackSize,
            isLandscape: layout.isLandscapeFullscreen,
            usesFullscreenLayout: layout.usesFullscreenLayout,
            activeFullscreenMode: layout.effectiveFullscreenMode,
            targetFullscreenMode: layout.targetFullscreenMode,
            isCompletingFullscreenExit: fullscreenCoordinator.isCompletingExit,
            isSystemRotationLayoutTransitioning: fullscreenCoordinator.isSystemRotationLayoutTransitioning,
            isDanmakuSettingsPresented: isShowingDanmakuSettings,
            runtimeSettings: runtimeSettings.snapshot
        )
    }
}
