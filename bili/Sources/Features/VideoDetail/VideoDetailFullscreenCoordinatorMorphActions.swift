import SwiftUI
import UIKit

extension VideoDetailFullscreenCoordinator {
    func updatePlayerSurfaceFrame(_ frame: CGRect) {
        guard frame.width > 1, frame.height > 1 else { return }
        latestPlayerSurfaceFrame = frame
        guard activeMode == nil,
              !isCompletingExit,
              !isSystemRotationLayoutTransitioning
        else { return }
        latestInlinePlayerSurfaceFrame = frame
    }

    func prepareEnterMorph(
        playerViewModel: PlayerStateViewModel?,
        orientation: UIDeviceOrientation,
        usesWindowMask wantsWindowMask: Bool = false
    ) {
        guard playerViewModel?.isTerminated != true else { return }
        guard let snapshot = resolvedMorphSnapshot(playerViewModel: playerViewModel) else {
            return
        }

        let sourceFrame = resolvedSourceFrame()
        let targetFrame = resolvedFullscreenFrame(orientation: orientation)
        guard sourceFrame.width > 1, sourceFrame.height > 1,
              targetFrame.width > 1, targetFrame.height > 1
        else { return }

        let usesWindowMask = wantsWindowMask
            && VideoDetailRotationWindowMask.hold(
                snapshot: snapshot,
                frame: sourceFrame
            )
        PlayerMetricsLog.diagnostic(
            "fullscreenEnter morphPrepare usesWindowMask=\(usesWindowMask) snapshotVideo=\(snapshot.isVideoFrame) source=\(sourceFrame) target=\(targetFrame)"
        )
        cancelPendingMorphTransitionTask()
        morphState = VideoDetailFullscreenMorphState(
            phase: .entering,
            snapshot: snapshot,
            sourceFrame: sourceFrame,
            targetFrame: targetFrame,
            orientation: orientation,
            usesWindowMask: usesWindowMask,
            progress: 0,
            opacity: 1
        )
        morphStartedAtNanoseconds = nil
    }

    func runPreparedEnterMorph() {
        guard let state = morphState, state.phase == .entering else { return }
        PlayerMetricsLog.diagnostic(
            "fullscreenEnter morphRun usesWindowMask=\(state.usesWindowMask) snapshotVideo=\(state.snapshot.isVideoFrame)"
        )
        animatePreparedMorph(phase: .entering)
        if state.usesWindowMask {
            _ = VideoDetailRotationWindowMask.animateHeldSnapshot(
                from: state.sourceFrame,
                to: state.targetFrame,
                duration: Self.morphTransitionDuration,
                releasesOnCompletion: false
            )
        } else {
            VideoDetailRotationWindowMask.remove()
        }
        // 进入全屏的淡出由系统旋转完成/兜底完成后统一触发；
        // 先确认横屏 surface 已经可显示，避免过早露出黑帧。
    }

    func runPreparedEnterMorphAfterLayout() {
        let revision = stateRevision
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self,
                  self.isCurrentStateRevision(revision),
                  self.morphState?.phase == .entering,
                  self.mode?.isLandscape == true
            else { return }
            self.runPreparedEnterMorph()
        }
    }

    func prepareExitMorph(playerViewModel: PlayerStateViewModel?) {
        guard let activeMode,
              activeMode.isLandscape,
              playerViewModel?.isTerminated != true
        else { return }
        let wantsWindowMask = shouldUseWindowSnapshotMask(for: playerViewModel)
        guard let snapshot = resolvedMorphSnapshot(playerViewModel: playerViewModel) else {
            PlayerMetricsLog.diagnostic("fullscreenExit morphPrepare skipped snapshot=false")
            return
        }

        let orientation: UIDeviceOrientation
        if case let .landscape(activeOrientation) = activeMode {
            orientation = activeOrientation
        } else {
            orientation = preferredLandscapeDeviceOrientation()
        }

        let sourceFrame = resolvedFullscreenFrame(orientation: orientation)
        let targetFrame = resolvedSourceFrame()
        guard sourceFrame.width > 1, sourceFrame.height > 1,
              targetFrame.width > 1, targetFrame.height > 1
        else { return }

        let usesWindowMask = wantsWindowMask
            && VideoDetailRotationWindowMask.hold(
                snapshot: snapshot,
                frame: sourceFrame
            )
        PlayerMetricsLog.diagnostic(
            "fullscreenExit morphPrepare usesWindowMask=\(usesWindowMask) snapshotVideo=\(snapshot.isVideoFrame) source=\(sourceFrame) target=\(targetFrame)"
        )
        cancelPendingMorphTransitionTask()
        morphState = VideoDetailFullscreenMorphState(
            phase: .exiting,
            snapshot: snapshot,
            sourceFrame: sourceFrame,
            targetFrame: targetFrame,
            orientation: orientation,
            usesWindowMask: usesWindowMask,
            progress: 0,
            opacity: 1
        )
        morphStartedAtNanoseconds = nil
    }

    func runPreparedExitMorph() {
        guard let state = morphState, state.phase == .exiting else { return }
        PlayerMetricsLog.diagnostic(
            "fullscreenExit morphRun usesWindowMask=\(state.usesWindowMask) snapshotVideo=\(state.snapshot.isVideoFrame)"
        )
        animatePreparedMorph(phase: .exiting)
        if state.usesWindowMask {
            _ = VideoDetailRotationWindowMask.animateHeldSnapshot(
                from: state.sourceFrame,
                to: state.targetFrame,
                duration: Self.morphTransitionDuration,
                releasesOnCompletion: false
            )
        } else {
            VideoDetailRotationWindowMask.remove()
        }
        // Exits are cleared by finishCompletingExit after the portrait surface is
        // ready, or after its explicit fallback wait. Letting this timer run here
        // can expose a not-yet-ready portrait surface mid-rotation.
    }

    func finishExitMorphAfterSurfaceSettle(
        delayNanoseconds: UInt64? = nil
    ) {
        // 进入/退出都在 surface 稳定后淡出快照。
        guard morphState != nil else { return }
        let requestedDelay = delayNanoseconds ?? Self.exitMorphSurfaceSettleDelayNanoseconds
        scheduleMorphFade(after: max(requestedDelay, remainingMorphCompletionDelayNanoseconds()))
    }

    func finishEnterMorphAfterSurfaceReady(
        playerViewModel: PlayerStateViewModel?,
        isCurrentPlayer: PlayerCurrentPredicate? = nil
    ) {
        guard morphState?.phase == .entering else { return }
        scheduleEnterMorphFadeAfterSurfaceReady(
            playerViewModel: playerViewModel,
            isCurrentPlayer: isCurrentPlayer
        )
    }

    func clearMorph(immediate: Bool = false) {
        cancelPendingMorphTransitionTask()
        PlayerMetricsLog.diagnostic("fullscreenMorph clear immediate=\(immediate)")
        guard immediate else {
            scheduleMorphFade(after: remainingMorphCompletionDelayNanoseconds())
            return
        }
        VideoDetailRotationWindowMask.remove()
        morphState = nil
        morphStartedAtNanoseconds = nil
    }

    private func scheduleMorphClear(after delay: UInt64) {
        cancelPendingMorphTransitionTask()
        let generation = advanceMorphTransitionGeneration()
        pendingMorphTransitionTask = Task { @MainActor [weak self] in
            defer {
                self?.clearPendingMorphTransitionTaskIfCurrent(generation: generation)
            }
            try? await Task.sleep(nanoseconds: delay)
            guard let self,
                  !Task.isCancelled,
                  self.morphTransitionGeneration == generation
            else { return }
            self.morphState = nil
            self.morphStartedAtNanoseconds = nil
        }
    }

    private func scheduleMorphFade(after delay: UInt64) {
        cancelPendingMorphTransitionTask()
        let generation = advanceMorphTransitionGeneration()
        pendingMorphTransitionTask = Task { @MainActor [weak self] in
            defer {
                self?.clearPendingMorphTransitionTaskIfCurrent(generation: generation)
            }
            try? await Task.sleep(nanoseconds: delay)
            guard let self,
                  !Task.isCancelled,
                  self.morphTransitionGeneration == generation
            else { return }
            VideoDetailRotationWindowMask.release(
                after: 0,
                fadeDuration: Self.morphFadeDurationNanoseconds
            )
            withAnimation(.easeOut(duration: Self.morphFadeDuration)) {
                self.morphState?.opacity = 0
            }
            try? await Task.sleep(nanoseconds: Self.morphClearDelayNanoseconds)
            guard !Task.isCancelled,
                  self.morphTransitionGeneration == generation
            else { return }
            self.morphState = nil
            self.morphStartedAtNanoseconds = nil
        }
    }

    private func scheduleEnterMorphFadeAfterSurfaceReady(
        playerViewModel: PlayerStateViewModel?,
        isCurrentPlayer: PlayerCurrentPredicate?
    ) {
        cancelPendingMorphTransitionTask()
        let generation = advanceMorphTransitionGeneration()
        let transitionGeneration = fullscreenTransitionGeneration
        pendingMorphTransitionTask = Task { @MainActor [weak self, weak playerViewModel, isCurrentPlayer] in
            defer {
                self?.clearPendingMorphTransitionTaskIfCurrent(generation: generation)
            }
            guard let self,
                  !Task.isCancelled,
                  self.morphTransitionGeneration == generation,
                  self.fullscreenTransitionGeneration == transitionGeneration,
                  self.morphState?.phase == .entering,
                  self.mode?.isLandscape == true
            else { return }

            let isReady = await self.waitForEnterSurfaceReadiness(
                playerViewModel: playerViewModel,
                isCurrentPlayer: isCurrentPlayer
            )
            PlayerMetricsLog.diagnostic(
                "fullscreenEnter readiness ready=\(isReady) playerReady=\(playerViewModel?.isCurrentPlaybackSurfaceReadyForDisplay == true)"
            )
            guard !Task.isCancelled,
                  self.morphTransitionGeneration == generation,
                  self.fullscreenTransitionGeneration == transitionGeneration,
                  self.morphState?.phase == .entering,
                  self.mode?.isLandscape == true
            else { return }

            let delay = max(
                Self.enterMorphSurfaceSettleDelayNanoseconds,
                self.remainingMorphCompletionDelayNanoseconds()
            )
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled,
                  self.morphTransitionGeneration == generation,
                  self.fullscreenTransitionGeneration == transitionGeneration,
                  self.morphState?.phase == .entering,
                  self.mode?.isLandscape == true
            else { return }
            VideoDetailRotationWindowMask.release(
                after: 0,
                fadeDuration: Self.morphFadeDurationNanoseconds
            )
            withAnimation(.easeOut(duration: Self.morphFadeDuration)) {
                self.morphState?.opacity = 0
            }
            try? await Task.sleep(nanoseconds: Self.morphClearDelayNanoseconds)
            guard !Task.isCancelled,
                  self.morphTransitionGeneration == generation,
                  self.fullscreenTransitionGeneration == transitionGeneration
            else { return }
            self.morphState = nil
            self.morphStartedAtNanoseconds = nil
        }
    }

    private func waitForEnterSurfaceReadiness(
        playerViewModel: PlayerStateViewModel?,
        isCurrentPlayer: PlayerCurrentPredicate?
    ) async -> Bool {
        guard let playerViewModel,
              canRefreshSurface(for: playerViewModel, isCurrentPlayer: isCurrentPlayer)
        else { return false }

        let startedAt = DispatchTime.now().uptimeNanoseconds
        var stableReadySamples = 0
        while DispatchTime.now().uptimeNanoseconds - startedAt < Self.enterSurfaceReadinessMaximumWaitNanoseconds {
            refreshActivePlayerSurfaceLayout(
                playerViewModel: playerViewModel,
                coordinatedWithSwiftUILayout: false,
                isCurrentPlayer: isCurrentPlayer
            )
            if playerViewModel.validateCurrentPlaybackSurfaceReadyForDisplay() {
                stableReadySamples += 1
                if stableReadySamples >= Self.enterSurfaceRequiredStableSamples {
                    return true
                }
            } else {
                stableReadySamples = 0
            }
            try? await Task.sleep(nanoseconds: Self.enterSurfaceReadinessPollDelayNanoseconds)
            guard !Task.isCancelled,
                  canRefreshSurface(for: playerViewModel, isCurrentPlayer: isCurrentPlayer)
            else { return false }
        }
        return false
    }

    private func animatePreparedMorph(phase: VideoDetailFullscreenMorphState.Phase) {
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self,
                  self.morphState?.phase == phase
            else { return }
            self.morphStartedAtNanoseconds = DispatchTime.now().uptimeNanoseconds
            withAnimation(Self.morphTransitionAnimation) {
                self.morphState?.progress = 1
            }
        }
    }

    private func remainingMorphCompletionDelayNanoseconds() -> UInt64 {
        guard let morphStartedAtNanoseconds else {
            return Self.morphTransitionCompletionDelayNanoseconds
        }
        let elapsed = DispatchTime.now().uptimeNanoseconds - morphStartedAtNanoseconds
        guard elapsed < Self.morphTransitionCompletionDelayNanoseconds else { return 0 }
        return Self.morphTransitionCompletionDelayNanoseconds - elapsed
    }

    private func resolvedSourceFrame() -> CGRect {
        if latestInlinePlayerSurfaceFrame.width > 1, latestInlinePlayerSurfaceFrame.height > 1 {
            return latestInlinePlayerSurfaceFrame
        }
        if activeMode == nil,
           latestPlayerSurfaceFrame.width > 1,
           latestPlayerSurfaceFrame.height > 1 {
            return latestPlayerSurfaceFrame
        }
        guard let window = UIApplication.shared.videoDetailKeyWindow
            ?? UIApplication.shared.biliForegroundKeyWindow
        else { return .null }
        let width = window.bounds.width
        let height = width * 9 / 16
        return CGRect(x: 0, y: window.safeAreaInsets.top, width: width, height: height)
    }

    private func resolvedFullscreenFrame(orientation: UIDeviceOrientation) -> CGRect {
        guard let window = UIApplication.shared.videoDetailKeyWindow
            ?? UIApplication.shared.biliForegroundKeyWindow
        else { return .null }
        let bounds = window.bounds
        guard orientation.isLandscape else { return bounds }

        let longSide = max(bounds.width, bounds.height)
        let shortSide = min(bounds.width, bounds.height)
        return CGRect(
            x: bounds.midX - longSide / 2,
            y: bounds.midY - shortSide / 2,
            width: longSide,
            height: shortSide
        )
    }

    private func resolvedMorphSnapshot(playerViewModel: PlayerStateViewModel?) -> PlaybackTransitionSnapshot? {
        if let snapshot = playerViewModel?.makeCurrentVideoFrameTransitionSnapshot()
            ?? playerViewModel?.makePlaybackTransitionSnapshot() {
            lastUsableMorphSnapshot = snapshot
            return snapshot
        }

        if let lastUsableMorphSnapshot {
            return lastUsableMorphSnapshot
        }

        return nil
    }

    private func shouldUseWindowSnapshotMask(for _: PlayerStateViewModel?) -> Bool {
        activeMode?.isLandscape == true
    }
}
