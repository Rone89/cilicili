import SwiftUI
import UIKit

extension VideoDetailFullscreenCoordinator {
    private static let exitSurfaceReadinessPollDelayNanoseconds: UInt64 = 16_000_000
    private static let exitSurfaceReadinessMaximumWaitNanoseconds: UInt64 = 820_000_000
    private static let exitSurfaceRequiredStableSamples = 2

    func restorePortraitWhenInactive() {
        guard mode == nil, !isCompletingExit else { return }
        AppOrientationLock.restorePortrait(in: UIApplication.shared.videoDetailKeyWindow?.windowScene)
    }

    func beginCompletingExit(
        playerViewModel: PlayerStateViewModel?,
        isCurrentPlayer: PlayerCurrentPredicate? = nil
    ) {
        guard let activeMode else { return }
        guard canRefreshSurface(for: playerViewModel, isCurrentPlayer: isCurrentPlayer) else {
            PlayerMetricsLog.diagnostic(
                "fullscreenExit beginWithoutSurfaceRefresh activeMode=\(activeMode) hasPlayer=\(playerViewModel != nil)"
            )
            advanceStateRevision()
            advanceFullscreenTransitionGeneration()
            cancelPendingFullscreenExitTask(advancesGeneration: false)
            exitingMode = nil
            setMode(
                nil,
                trigger: .none,
                animated: false,
                playerViewModel: nil,
                isCurrentPlayer: isCurrentPlayer
            )
            finishCompletingExitWithoutSurfaceRefresh()
            return
        }
        let isRotationTriggered = trigger == .rotation
        let needsPortraitRotationTransition = activeMode.isLandscape
        PlayerMetricsLog.diagnostic(
            "fullscreenExit begin activeMode=\(activeMode) rotation=\(isRotationTriggered) portraitRotation=\(needsPortraitRotationTransition) playerFrame=\(latestPlayerSurfaceFrame) inlineFrame=\(latestInlinePlayerSurfaceFrame)"
        )
        advanceStateRevision()
        let transitionGeneration = advanceFullscreenTransitionGeneration()
        cancelPendingFullscreenExitTask(advancesGeneration: false)
        cancelPendingSurfaceLayoutRefreshTask()
        prepareExitMorph(playerViewModel: playerViewModel)
        exitingMode = activeMode
        isCompletingExit = true
        if needsPortraitRotationTransition {
            isSystemRotationLayoutTransitioning = true
            scheduleRotationLayoutTransitionFallbackFinish(
                playerViewModel: playerViewModel,
                isCurrentPlayer: isCurrentPlayer
            )
        }
        runPreparedExitMorph()
        setMode(
            nil,
            trigger: .none,
            animated: !isRotationTriggered && !needsPortraitRotationTransition,
            playerViewModel: playerViewModel,
            isCurrentPlayer: isCurrentPlayer
        )
        requestInlinePortraitGeometryAfterLayout()
        let exitStateRevision = stateRevision
        pendingFullscreenExitTask = Task { @MainActor [weak self, weak playerViewModel, isCurrentPlayer] in
            defer {
                self?.clearPendingFullscreenExitTaskIfCurrent(generation: transitionGeneration)
            }
            try? await Task.sleep(nanoseconds: Self.inlineTransitionCompletionDelayNanoseconds)
            guard !Task.isCancelled,
                  self?.fullscreenTransitionGeneration == transitionGeneration,
                  self?.isCurrentStateRevision(exitStateRevision) == true
            else { return }
            guard let self,
                  self.canRefreshSurface(for: playerViewModel, isCurrentPlayer: isCurrentPlayer)
            else {
                self?.finishCompletingExitWithoutSurfaceRefresh()
                return
            }
            let isReady = await self.waitForPortraitExitSurfaceReadiness(
                playerViewModel: playerViewModel,
                isCurrentPlayer: isCurrentPlayer
            )
            PlayerMetricsLog.diagnostic(
                "fullscreenExit readiness ready=\(isReady) playerReady=\(playerViewModel?.isCurrentPlaybackSurfaceReadyForDisplay == true)"
            )
            self.finishCompletingExit(
                playerViewModel: playerViewModel,
                surfaceReadyForDisplay: isReady,
                isCurrentPlayer: isCurrentPlayer
            )
        }
    }

    func finishCompletingExit(
        playerViewModel: PlayerStateViewModel?,
        surfaceReadyForDisplay: Bool = true,
        isCurrentPlayer: PlayerCurrentPredicate? = nil
    ) {
        PlayerMetricsLog.diagnostic(
            "fullscreenExit finish surfaceReady=\(surfaceReadyForDisplay) currentSurfaceReady=\(playerViewModel?.isCurrentPlaybackSurfaceReadyForDisplay == true) playerFrame=\(latestPlayerSurfaceFrame) inlineFrame=\(latestInlinePlayerSurfaceFrame)"
        )
        advanceStateRevision()
        withoutAnimation {
            exitingMode = nil
            isCompletingExit = false
        }
        restorePortraitWhenInactive()
        refreshActivePlayerSurfaceLayout(
            playerViewModel: playerViewModel,
            coordinatedWithSwiftUILayout: true,
            isCurrentPlayer: isCurrentPlayer
        )
        if surfaceReadyForDisplay {
            clearMorph() // 竖屏 surface 就绪后淡出快照，收尾
        } else {
            finishExitMorphAfterSurfaceSettle(delayNanoseconds: Self.exitMorphFallbackFadeDelayNanoseconds)
        }
        clearPendingFullscreenExitTaskIfCurrent(generation: fullscreenTransitionGeneration)
    }

    func finishCompletingExitWithoutSurfaceRefresh() {
        PlayerMetricsLog.diagnostic("fullscreenExit finishWithoutSurfaceRefresh")
        advanceStateRevision()
        withoutAnimation {
            exitingMode = nil
            isCompletingExit = false
        }
        restorePortraitWhenInactive()
        cancelPendingSurfaceLayoutRefreshTask()
        clearPendingFullscreenExitTaskIfCurrent(generation: fullscreenTransitionGeneration)
    }

    private func withoutAnimation(_ update: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, update)
    }

    private func waitForPortraitExitSurfaceReadiness(
        playerViewModel: PlayerStateViewModel?,
        isCurrentPlayer: PlayerCurrentPredicate?
    ) async -> Bool {
        guard let playerViewModel,
              canRefreshSurface(for: playerViewModel, isCurrentPlayer: isCurrentPlayer)
        else { return false }

        let startedAt = DispatchTime.now().uptimeNanoseconds
        var stableReadySamples = 0
        while DispatchTime.now().uptimeNanoseconds - startedAt < Self.exitSurfaceReadinessMaximumWaitNanoseconds {
            refreshActivePlayerSurfaceLayout(
                playerViewModel: playerViewModel,
                coordinatedWithSwiftUILayout: false,
                isCurrentPlayer: isCurrentPlayer
            )
            if playerViewModel.validateCurrentPlaybackSurfaceReadyForDisplay() {
                stableReadySamples += 1
                if stableReadySamples >= Self.exitSurfaceRequiredStableSamples {
                    return true
                }
            } else {
                stableReadySamples = 0
            }
            try? await Task.sleep(nanoseconds: Self.exitSurfaceReadinessPollDelayNanoseconds)
            guard !Task.isCancelled,
                  canRefreshSurface(for: playerViewModel, isCurrentPlayer: isCurrentPlayer)
            else { return false }
        }
        return false
    }

}
