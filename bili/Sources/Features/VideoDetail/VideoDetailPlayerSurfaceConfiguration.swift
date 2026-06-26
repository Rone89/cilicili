import SwiftUI

struct VideoDetailPlayerSurfaceConfiguration {
    let isLandscape: Bool
    let playerWidth: CGFloat?
    let playerHeight: CGFloat
    let fullscreenMode: PlayerFullscreenMode?
    let isLayoutTransitioning: Bool
    let suppressesPosterDuringFullscreenTransition: Bool
    let isDanmakuSettingsPresented: Bool
    let showsPlaybackControls: Bool

    var usesLandscapePlaybackChrome: Bool {
        isLandscape || fullscreenMode?.isLandscape == true
    }
}
