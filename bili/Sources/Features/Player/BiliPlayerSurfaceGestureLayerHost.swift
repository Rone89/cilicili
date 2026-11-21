import SwiftUI

struct BiliPlayerSurfaceGestureLayerHost<Content: View>: View {
    @EnvironmentObject private var libraryStore: LibraryStore

    let content: Content
    let visibilityActions: BiliPlayerPlaybackControlsVisibilityActions
    let speedBoostActions: BiliPlayerSpeedBoostActions
    let viewModel: PlayerStateViewModel
    let allowsDoubleTapPlaybackToggle: Bool
    let seekPreviewModel: PlayerSeekPreviewModel
    let seekPreviewAPI: BiliAPIClient?
    let seekPreviewContext: PlayerSeekPreviewContext?
    let holdCurrentFrameForSeek: () -> Void
    let prepareUserSeekWarmup: (Double, Bool) -> Void
    let resetPreparedScrubProgress: () -> Void
    var isFullscreenActive: Bool = false
    var onRequestFullscreen: (() -> Void)? = nil
    var onExitFullscreen: (() -> Void)? = nil

    private var gestureActions: BiliPlayerSurfaceGestureActions {
        BiliPlayerSurfaceGestureActions(
            viewModel: viewModel,
            visibilityActions: visibilityActions,
            speedBoostActions: speedBoostActions,
            holdCurrentFrameForSeek: holdCurrentFrameForSeek,
            prepareUserSeekWarmup: prepareUserSeekWarmup,
            resetPreparedScrubProgress: resetPreparedScrubProgress
        )
    }

    var body: some View {
        BiliPlayerSurfaceGestureLayer(
            content: content,
            clock: viewModel.playbackClock,
            durationHint: viewModel.displayDuration,
            canSeek: viewModel.canSeek,
            allowsDoubleTapPlaybackToggle: allowsDoubleTapPlaybackToggle,
            onSingleTap: gestureActions.singleTap,
            onDoubleTap: gestureActions.doubleTap,
            onBeginSpeedBoost: gestureActions.beginSpeedBoost,
            onUpdateSpeedBoost: gestureActions.updateSpeedBoost(horizontalOffset:verticalOffset:),
            onEndSpeedBoost: gestureActions.endSpeedBoost(reason:),
            onHorizontalSeekStart: { progress in
                seekPreviewModel.beginScrub(
                    api: seekPreviewAPI,
                    context: seekPreviewContext,
                    source: .surfaceGesture,
                    progress: progress,
                    duration: resolvedDuration
                )
                gestureActions.horizontalSeekStart(progress)
            },
            onHorizontalSeekChanged: { progress, horizontalVelocity in
                seekPreviewModel.updateScrub(progress: progress, duration: resolvedDuration)
                gestureActions.horizontalSeekChanged(progress, horizontalVelocity: horizontalVelocity)
            },
            onHorizontalSeekEnded: { progress in
                seekPreviewModel.endScrub()
                gestureActions.horizontalSeekEnded(progress)
            },
            onHorizontalSeekCancelled: {
                seekPreviewModel.endScrub()
                gestureActions.horizontalSeekCancelled()
            },
            onHorizontalSeekCancelPendingChanged: { isPending in
                seekPreviewModel.setCancellationPending(isPending)
            },
            threeZoneVerticalGestureEnabled: libraryStore.playerThreeZoneVerticalGestureEnabled,
            isFullscreenActive: isFullscreenActive,
            onRequestFullscreen: onRequestFullscreen,
            onExitFullscreen: onExitFullscreen
        )
        .id(ObjectIdentifier(viewModel))
        .onDisappear {
            seekPreviewModel.endScrub()
            speedBoostActions.end(reason: .disappear)
        }
    }

    private var resolvedDuration: TimeInterval {
        viewModel.playbackClock.duration ?? viewModel.displayDuration ?? 0
    }
}
