import SwiftUI

struct VideoDetailStandardPlaybackContainerConfig {
    let screenSize: CGSize
    let isLandscape: Bool
    let usesFullscreenLayout: Bool
    let activeFullscreenMode: PlayerFullscreenMode?
    let targetFullscreenMode: PlayerFullscreenMode?
    let isCompletingFullscreenExit: Bool
    let isSystemRotationLayoutTransitioning: Bool
    let isDanmakuSettingsPresented: Bool
    let runtimeSettings: VideoDetailRuntimeSettingsSnapshot
}
