import SwiftUI

struct VideoDetailPinnedDynamicPlayerHeaderConfig {
    let screenSize: CGSize
    let playerWidth: CGFloat?
    let playerHeight: CGFloat
    let isLandscape: Bool
    let isFullscreen: Bool
    let fullscreenMode: PlayerFullscreenMode?
    let targetFullscreenMode: PlayerFullscreenMode?
    let isLayoutTransitioning: Bool
    let suppressesPosterDuringFullscreenTransition: Bool
    let isDanmakuSettingsPresented: Bool
    let showsPinnedProgressBar: Bool
    let onRequestFullscreen: (PlayerStateViewModel) -> Void
    let onExitFullscreen: (() -> Void)?
    let onNavigateBack: () -> Void
    let onShowDanmakuSettings: () -> Void
}
