import Foundation

struct VideoDetailPlayerSurfaceOptionsBuilder {
    let context: VideoDetailPlayerSurfaceContext
    let surfaceStore: VideoDetailPlayerSurfaceRenderStore
    let configuration: VideoDetailPlayerSurfaceConfiguration
    let allowsPlaybackActivation: () -> Bool

    var options: BiliPlayerViewOptions {
        BiliPlayerViewOptions(
            presentation: context.presentation,
            showsNavigationChrome: false,
            showsPlaybackControls: context.showsPlaybackControls,
            showsStartupLoadingIndicator: false,
            pausesOnDisappear: false,
            surfaceOverlay: context.surfaces.surfaceOverlay,
            controlsAccessory: context.surfaces.controlsAccessory,
            topLeadingControlsAccessory: context.surfaces.topLeadingControlsAccessory,
            isDanmakuEnabled: surfaceStore.isDanmakuEnabled,
            onToggleDanmaku: context.controls.onToggleDanmaku,
            onShowDanmakuSettings: context.controls.onShowDanmakuSettings,
            isSecondaryControlsPresented: context.isSecondaryControlsPresented,
            durationHint: surfaceStore.duration,
            keepsPlayerSurfaceStable: true,
            fullscreenMode: configuration.fullscreenMode,
            isLayoutTransitioning: configuration.isLayoutTransitioning,
            usesLiveSurfaceDuringLayoutTransition: true,
            onPrepareForUserSeek: context.controls.onPrepareForUserSeek,
            onRequestFullscreen: context.controls.onRequestFullscreen,
            onExitFullscreen: context.controls.onExitFullscreen,
            allowsPlaybackActivation: allowsPlaybackActivation
        )
    }
}
