import SwiftUI

struct BiliPlayerViewContent: View {
    let context: BiliPlayerViewRenderContext
    let renderState: BiliPlayerViewRenderState

    var body: some View {
        BiliPlayerSurfaceChrome(
            playbackSurface: AnyView(surfaceGestureLayer),
            state: surfaceChromeState,
            playbackControls: AnyView(playbackControls)
        )
    }

    private var surfaceGestureLayer: some View {
        BiliPlayerSurfaceGestureLayerHost(
            content: playbackSurface,
            visibilityActions: renderState.visibilityActions,
            speedBoostActions: renderState.speedBoostActions,
            viewModel: context.viewModel
        )
    }

    private var playbackSurface: some View {
        VideoSurfaceView(
            viewModel: context.viewModel,
            prefersNativePlaybackControls: false,
            disablesImplicitLayoutAnimations: context.configuration.isLayoutTransitioning,
            usesLiveSurfaceDuringLayoutTransition: context.configuration.usesLiveSurfaceDuringLayoutTransition
        )
    }

    private var playbackControls: some View {
        BiliPlayerNativeControlsHost(
            context: context,
            renderState: renderState
        )
    }

    private var surfaceChromeState: BiliPlayerSurfaceChromeState {
        BiliPlayerSurfaceChromeState(
            presentation: context.configuration.presentation,
            surfaceOverlay: context.configuration.surfaceOverlay,
            rotationSnapshot: context.rotationTransitionSnapshotModel.snapshot,
            rotationFallbackCoverURL: context.rotationFallbackCoverURL,
            rotationSnapshotOpacity: context.rotationTransitionSnapshotModel.opacity,
            constrainsRotationSnapshotToVideoAspect: context.configuration.isFullscreenActive
                || context.configuration.isLayoutTransitioning,
            showsPlayerLoadingChrome: renderState.showsPlayerLoadingChrome,
            isBuffering: context.surfaceState.isBuffering,
            showsInlineLoadingProgress: renderState.showsInlineLoadingProgress,
            isUserSeeking: context.surfaceState.isUserSeeking,
            isSpeedBoostActive: context.speedBoostModel.isActive,
            showsActivePlaybackControls: renderState.showsActivePlaybackControls,
            topLeadingControlsAccessory: context.configuration.topLeadingControlsAccessory,
            isFullscreenActive: context.configuration.isFullscreenActive,
            controlsBottomLift: context.configuration.controlsBottomLift,
            errorMessage: context.surfaceState.errorMessage
        )
    }
}
