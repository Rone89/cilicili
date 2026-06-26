import SwiftUI

struct BiliPlayerViewConfiguration {
    let presentation: BiliPlayerPresentation
    let showsNavigationChrome: Bool
    let showsPlaybackControls: Bool
    let showsStartupLoadingIndicator: Bool
    let pausesOnDisappear: Bool
    let surfaceOverlay: AnyView?
    let controlsAccessory: AnyView?
    let topLeadingControlsAccessory: AnyView?
    let controlsBottomLift: CGFloat
    let isDanmakuEnabled: Bool
    let onToggleDanmaku: (() -> Void)?
    let onShowDanmakuSettings: (() -> Void)?
    let isSecondaryControlsPresented: Bool
    let durationHint: TimeInterval?
    let embeddedAspectRatio: CGFloat
    let ignoresContainerSafeArea: Bool
    let keepsPlayerSurfaceStable: Bool
    let fullscreenMode: PlayerFullscreenMode?
    let isLayoutTransitioning: Bool
    let usesLiveSurfaceDuringLayoutTransition: Bool
    let onPrepareForUserSeek: ((Double) -> Void)?
    let onRequestFullscreen: (() -> Void)?
    let onExitFullscreen: (() -> Void)?
    let allowsPlaybackActivation: (() -> Bool)?

    var isFullscreenActive: Bool {
        fullscreenMode != nil
    }

    var canToggleFullscreen: Bool {
        if isFullscreenActive {
            return onExitFullscreen != nil
        }
        return onRequestFullscreen != nil
    }

    init(
        presentation: BiliPlayerPresentation,
        showsNavigationChrome: Bool,
        showsPlaybackControls: Bool,
        showsStartupLoadingIndicator: Bool,
        pausesOnDisappear: Bool,
        surfaceOverlay: AnyView?,
        controlsAccessory: AnyView?,
        topLeadingControlsAccessory: AnyView?,
        controlsBottomLift: CGFloat,
        isDanmakuEnabled: Bool,
        onToggleDanmaku: (() -> Void)?,
        onShowDanmakuSettings: (() -> Void)?,
        isSecondaryControlsPresented: Bool,
        durationHint: TimeInterval?,
        embeddedAspectRatio: CGFloat,
        ignoresContainerSafeArea: Bool,
        keepsPlayerSurfaceStable: Bool,
        fullscreenMode: PlayerFullscreenMode?,
        isLayoutTransitioning: Bool,
        usesLiveSurfaceDuringLayoutTransition: Bool,
        onPrepareForUserSeek: ((Double) -> Void)?,
        onRequestFullscreen: (() -> Void)?,
        onExitFullscreen: (() -> Void)?,
        allowsPlaybackActivation: (() -> Bool)?
    ) {
        self.presentation = presentation
        self.showsNavigationChrome = showsNavigationChrome
        self.showsPlaybackControls = showsPlaybackControls
        self.showsStartupLoadingIndicator = showsStartupLoadingIndicator
        self.pausesOnDisappear = pausesOnDisappear
        self.surfaceOverlay = surfaceOverlay
        self.controlsAccessory = controlsAccessory
        self.topLeadingControlsAccessory = topLeadingControlsAccessory
        self.controlsBottomLift = controlsBottomLift
        self.isDanmakuEnabled = isDanmakuEnabled
        self.onToggleDanmaku = onToggleDanmaku
        self.onShowDanmakuSettings = onShowDanmakuSettings
        self.isSecondaryControlsPresented = isSecondaryControlsPresented
        self.durationHint = durationHint
        self.embeddedAspectRatio = embeddedAspectRatio
        self.ignoresContainerSafeArea = ignoresContainerSafeArea
        self.keepsPlayerSurfaceStable = keepsPlayerSurfaceStable
        self.fullscreenMode = fullscreenMode
        self.isLayoutTransitioning = isLayoutTransitioning
        self.usesLiveSurfaceDuringLayoutTransition = usesLiveSurfaceDuringLayoutTransition
        self.onPrepareForUserSeek = onPrepareForUserSeek
        self.onRequestFullscreen = onRequestFullscreen
        self.onExitFullscreen = onExitFullscreen
        self.allowsPlaybackActivation = allowsPlaybackActivation
    }

}
