import AVFoundation
import SwiftUI

struct BiliPlayerLifecycleActionBuilder {
    let viewModel: PlayerStateViewModel
    let surfaceState: PlayerSurfaceStateModel
    let playbackControlsVisibility: PlayerPlaybackControlsVisibilityModel
    let rotationTransitionSnapshotModel: PlayerRotationTransitionSnapshotModel
    let speedBoostModel: PlayerSpeedBoostModel
    let playbackProgressCoordinator: PlayerPlaybackProgressCoordinator
    let progressReporter: PlayerPlaybackProgressReporter
    let progressContext: PlayerPlaybackProgressContext
    let configuration: BiliPlayerViewConfiguration
    let isPictureInPictureEnabled: Bool
    let defaultPlaybackRate: Double
    let videoGravity: AVLayerVideoGravity

    var actions: BiliPlayerLifecycleActions {
        BiliPlayerLifecycleActions(
            onAppear: handleAppear,
            onScenePhaseChanged: handleScenePhaseChange,
            onDidBecomeActive: handleDidBecomeActive,
            onDisappear: handleDisappear,
            onFullscreenActiveChanged: handleFullscreenActiveChange,
            onPresentationChanged: handlePresentationChange,
            onLayoutTransitionChanged: handleLayoutTransitionChange,
            onSecondaryControlsPresentedChanged: handleSecondaryControlsPresentedChange,
            onPictureInPictureEnabledChanged: handlePictureInPictureEnabledChange
        )
    }

    private var visibilityActions: BiliPlayerPlaybackControlsVisibilityActions {
        BiliPlayerPlaybackControlsVisibilityActions(
            playbackControlsVisibility: playbackControlsVisibility,
            configuration: configuration
        )
    }

    private var speedBoostActions: BiliPlayerSpeedBoostActions {
        BiliPlayerSpeedBoostActions(
            viewModel: viewModel,
            surfaceState: surfaceState,
            speedBoostModel: speedBoostModel,
            visibilityActions: visibilityActions
        )
    }

    private func handleAppear() {
        guard !viewModel.isTerminated else { return }
        guard allowsPlaybackActivation else { return }
        surfaceState.bind(viewModel: viewModel)
        visibilityActions.syncSecondaryControlsPresentation(configuration.isSecondaryControlsPresented)
        viewModel.setPictureInPictureEnabled(isPictureInPictureEnabled)
        applyVideoGravity()
        applyPlaybackDefaults()
        if viewModel.wantsAutoplay {
            viewModel.play()
        }
        progressReporter.start(clock: viewModel.playbackClock) { time in
            playbackProgressCoordinator.saveProgress(time, context: progressContext)
        }
        if configuration.isLayoutTransitioning {
            handleLayoutTransitionChange(true)
        } else {
            visibilityActions.scheduleAutoHide()
        }
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        guard !viewModel.isTerminated else { return }
        if phase == .active {
            guard allowsPlaybackActivation else { return }
            viewModel.recoverPlaybackAfterTransientSystemOverlayIfNeeded()
            viewModel.recoverPlaybackAfterAppResume()
            restoreInlinePlaybackFromPictureInPictureIfNeeded()
        } else if phase == .inactive {
            guard allowsPlaybackActivation else { return }
            viewModel.preservePlaybackThroughTransientSystemOverlay()
        } else if phase == .background {
            if allowsPlaybackActivation {
                if isPictureInPictureEnabled {
                    viewModel.preservePlaybackThroughTransientSystemOverlay()
                } else {
                    viewModel.pauseForAppBackground()
                }
            }
            speedBoostActions.end(reason: "background")
            Task {
                await VideoPreloadCenter.shared.cancelAll()
            }
            playbackProgressCoordinator.saveProgressInBackground(
                currentTime: viewModel.currentTime,
                context: progressContext
            )
        }
    }

    private func handleDidBecomeActive() {
        guard !viewModel.isTerminated else { return }
        guard allowsPlaybackActivation else { return }
        viewModel.recoverPlaybackAfterTransientSystemOverlayIfNeeded()
        viewModel.recoverPlaybackAfterAppResume()
        restoreInlinePlaybackFromPictureInPictureIfNeeded()
    }

    private func handleDisappear() {
        speedBoostActions.end(reason: "disappear")
        progressReporter.stop()
        visibilityActions.cancelAutoHide()
        rotationTransitionSnapshotModel.release(immediate: true)
        playbackProgressCoordinator.endBackgroundTaskIfNeeded()
        guard !viewModel.isTerminated else { return }
        playbackProgressCoordinator.saveProgress(viewModel.currentTime, context: progressContext)
        guard configuration.pausesOnDisappear else { return }
        guard !configuration.isFullscreenActive else { return }
        viewModel.suspendForNavigation()
    }

    private func handleFullscreenActiveChange() {
        guard !viewModel.isTerminated else { return }
        guard allowsPlaybackActivation else { return }
        if !configuration.isLayoutTransitioning {
            releaseRotationSnapshotAfterSurfaceSettle()
        }
        applyVideoGravity()
        visibilityActions.show(scheduleAutoHide: true, animated: !configuration.isLayoutTransitioning)
    }

    private func handlePresentationChange() {
        guard !viewModel.isTerminated else { return }
        guard allowsPlaybackActivation else { return }
        applyVideoGravity()
        visibilityActions.show(scheduleAutoHide: true, animated: !configuration.isLayoutTransitioning)
    }

    private func handleLayoutTransitionChange(_ isTransitioning: Bool) {
        guard !viewModel.isTerminated else { return }
        guard allowsPlaybackActivation else { return }
        if isTransitioning {
            // Even when the live surface is kept during handoff, real devices can
            // briefly expose a blank drawable while AVPlayerLayer/KSPlayer relayouts.
            // Keep a component-level video frame over the player only; do not use a
            // window-level black mask that hides the system rotation animation.
            rotationTransitionSnapshotModel.hold(
                hasPresentedPlayback: viewModel.hasPresentedPlayback,
                surfaceLayoutGeneration: viewModel.surfaceLayoutGeneration,
                makeSnapshot: { [viewModel] in
                    viewModel.makeCurrentVideoFrameTransitionSnapshot()
                        ?? viewModel.makePlaybackTransitionSnapshot()
                }
            )
            viewModel.stabilizeSurfaceLayoutAfterGeometryChange()
            visibilityActions.cancelAutoHide()
            visibilityActions.show(scheduleAutoHide: false, animated: false)
        } else {
            viewModel.stabilizeSurfaceLayoutAfterGeometryChange()
            visibilityActions.show(scheduleAutoHide: true, animated: false)
            // 旋转布局结束：等 surface 真正就绪出帧后再淡出快照（轮询 ready，连续稳定再 reveal）。
            releaseRotationSnapshotAfterSurfaceSettle()
        }
    }

    private func handleSecondaryControlsPresentedChange(_ isPresented: Bool) {
        guard !viewModel.isTerminated else { return }
        guard allowsPlaybackActivation else { return }
        visibilityActions.syncSecondaryControlsPresentation(isPresented)
    }

    private func handlePictureInPictureEnabledChange(_ isEnabled: Bool) {
        guard !viewModel.isTerminated else { return }
        viewModel.setPictureInPictureEnabled(isEnabled)
        guard !isEnabled else { return }
        viewModel.stopPictureInPictureIfNeeded()
    }

    private var allowsPlaybackActivation: Bool {
        configuration.allowsPlaybackActivation?() ?? true
    }

    private func applyVideoGravity() {
        viewModel.setVideoGravity(videoGravity)
    }

    private func applyPlaybackDefaults() {
        viewModel.setPlaybackRate(BiliPlaybackRate(rawValue: defaultPlaybackRate) ?? .x10)
    }

    private func releaseRotationSnapshotAfterSurfaceSettle() {
        rotationTransitionSnapshotModel.releaseForStableSurfaceTransition(
            isReadyForReveal: { [viewModel] in
                viewModel.validateCurrentPlaybackSurfaceReadyForReveal()
            },
            makeRevealSnapshot: { [viewModel] in
                viewModel.makeCurrentVisibleSurfaceTransitionSnapshot()
                    ?? viewModel.makeCurrentVideoFrameTransitionSnapshot()
            }
        )
    }

    private func restoreInlinePlaybackFromPictureInPictureIfNeeded() {
        guard isPictureInPictureEnabled else { return }
        Task { @MainActor [viewModel] in
            _ = await viewModel.restoreInlinePlaybackFromPictureInPictureIfNeeded()
        }
    }

}
