import SwiftUI

struct BiliPlayerViewOptions {
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

    init(
        presentation: BiliPlayerPresentation = .fullScreen,
        showsNavigationChrome: Bool = true,
        showsPlaybackControls: Bool = true,
        showsStartupLoadingIndicator: Bool = true,
        pausesOnDisappear: Bool = true,
        surfaceOverlay: AnyView? = nil,
        controlsAccessory: AnyView? = nil,
        topLeadingControlsAccessory: AnyView? = nil,
        controlsBottomLift: CGFloat = 0,
        isDanmakuEnabled: Bool = true,
        onToggleDanmaku: (() -> Void)? = nil,
        onShowDanmakuSettings: (() -> Void)? = nil,
        isSecondaryControlsPresented: Bool = false,
        durationHint: TimeInterval? = nil,
        embeddedAspectRatio: CGFloat = 16 / 9,
        ignoresContainerSafeArea: Bool = true,
        keepsPlayerSurfaceStable: Bool = false,
        fullscreenMode: PlayerFullscreenMode? = nil,
        isLayoutTransitioning: Bool = false,
        usesLiveSurfaceDuringLayoutTransition: Bool = false,
        onPrepareForUserSeek: ((Double) -> Void)? = nil,
        onRequestFullscreen: (() -> Void)? = nil,
        onExitFullscreen: (() -> Void)? = nil,
        allowsPlaybackActivation: (() -> Bool)? = nil
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

    func configuration() -> BiliPlayerViewConfiguration {
        BiliPlayerViewConfiguration(
            presentation: presentation,
            showsNavigationChrome: showsNavigationChrome,
            showsPlaybackControls: showsPlaybackControls,
            showsStartupLoadingIndicator: showsStartupLoadingIndicator,
            pausesOnDisappear: pausesOnDisappear,
            surfaceOverlay: surfaceOverlay,
            controlsAccessory: controlsAccessory,
            topLeadingControlsAccessory: topLeadingControlsAccessory,
            controlsBottomLift: controlsBottomLift,
            isDanmakuEnabled: isDanmakuEnabled,
            onToggleDanmaku: onToggleDanmaku,
            onShowDanmakuSettings: onShowDanmakuSettings,
            isSecondaryControlsPresented: isSecondaryControlsPresented,
            durationHint: durationHint,
            embeddedAspectRatio: embeddedAspectRatio,
            ignoresContainerSafeArea: ignoresContainerSafeArea,
            keepsPlayerSurfaceStable: keepsPlayerSurfaceStable,
            fullscreenMode: fullscreenMode,
            isLayoutTransitioning: isLayoutTransitioning,
            usesLiveSurfaceDuringLayoutTransition: usesLiveSurfaceDuringLayoutTransition,
            onPrepareForUserSeek: onPrepareForUserSeek,
            onRequestFullscreen: onRequestFullscreen,
            onExitFullscreen: onExitFullscreen,
            allowsPlaybackActivation: allowsPlaybackActivation
        )
    }
}
