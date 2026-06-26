import SwiftUI

extension VideoDetailFullscreenCoordinator {
    private static let rotationLayoutTransitionFallbackNanoseconds: UInt64 = 520_000_000

    func beginSystemRotationLayoutTransition(
        playerViewModel: PlayerStateViewModel?,
        isCurrentPlayer: PlayerCurrentPredicate? = nil
    ) {
        guard canRefreshSurface(for: playerViewModel, isCurrentPlayer: isCurrentPlayer) else { return }
        if !isSystemRotationLayoutTransitioning {
            isSystemRotationLayoutTransitioning = true
        }
        scheduleRotationLayoutTransitionFallbackFinish(
            playerViewModel: playerViewModel,
            isCurrentPlayer: isCurrentPlayer
        )
        refreshActivePlayerSurfaceLayout(
            playerViewModel: playerViewModel,
            coordinatedWithSwiftUILayout: true,
            isCurrentPlayer: isCurrentPlayer
        )
    }

    func refreshActivePlayerSurfaceLayout(
        playerViewModel: PlayerStateViewModel?,
        coordinatedWithSwiftUILayout: Bool = false,
        isCurrentPlayer: PlayerCurrentPredicate? = nil
    ) {
        guard let playerViewModel,
              canRefreshSurface(for: playerViewModel, isCurrentPlayer: isCurrentPlayer)
        else {
            cancelPendingSurfaceLayoutRefreshTask()
            return
        }
        guard coordinatedWithSwiftUILayout else {
            playerViewModel.refreshSurfaceLayout()
            return
        }

        cancelPendingSurfaceLayoutRefreshTask(advancesGeneration: false)
        let refreshGeneration = advanceSurfaceLayoutRefreshGeneration()
        let baselineStateRevision = stateRevision
        pendingSurfaceLayoutRefreshTask = Task { @MainActor [weak self, weak playerViewModel, isCurrentPlayer] in
            defer {
                self?.clearPendingSurfaceLayoutRefreshTaskIfCurrent(generation: refreshGeneration)
            }
            await Task.yield()
            guard let self,
                  let playerViewModel,
                  self.canRefreshSurface(for: playerViewModel, isCurrentPlayer: isCurrentPlayer),
                  !Task.isCancelled,
                  self.isCurrentStateRevision(baselineStateRevision),
                  self.surfaceLayoutRefreshGeneration == refreshGeneration
            else { return }
            playerViewModel.refreshSurfaceLayout()

            for delay in VideoDetailFullscreenSurfaceRefreshSchedule.coordinatedDelays {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled,
                      self.isCurrentStateRevision(baselineStateRevision),
                      self.canRefreshSurface(for: playerViewModel, isCurrentPlayer: isCurrentPlayer),
                      self.surfaceLayoutRefreshGeneration == refreshGeneration
                else { return }
                playerViewModel.refreshSurfaceLayout()
            }
        }
    }

    func finishSystemRotationLayoutTransition(
        playerViewModel: PlayerStateViewModel?,
        isCurrentPlayer: PlayerCurrentPredicate? = nil
    ) {
        cancelPendingRotationLayoutTransitionFinishTask(advancesGeneration: false)
        isSystemRotationLayoutTransitioning = false
        refreshActivePlayerSurfaceLayout(
            playerViewModel: playerViewModel,
            coordinatedWithSwiftUILayout: true,
            isCurrentPlayer: isCurrentPlayer
        )
        finishExitMorphAfterSurfaceSettle()
    }

    func schedulePortraitExitSurfaceSettleFinish(
        playerViewModel: PlayerStateViewModel?,
        isCurrentPlayer: PlayerCurrentPredicate?
    ) {
        cancelPendingPortraitExitSurfaceSettleTask(advancesGeneration: false)
        let generation = advanceRotationLayoutTransitionGeneration()
        pendingPortraitExitSurfaceSettleTask = Task { @MainActor [weak self, weak playerViewModel, isCurrentPlayer] in
            defer {
                self?.clearPendingPortraitExitSurfaceSettleTaskIfCurrent(generation: generation)
            }
            try? await Task.sleep(nanoseconds: Self.portraitExitSurfaceSettleDelayNanoseconds)
            guard let self,
                  !Task.isCancelled,
                  self.rotationLayoutTransitionGeneration == generation,
                  self.isSystemRotationLayoutTransitioning
            else { return }

            self.isSystemRotationLayoutTransitioning = false
            self.refreshActivePlayerSurfaceLayout(
                playerViewModel: playerViewModel,
                coordinatedWithSwiftUILayout: true,
                isCurrentPlayer: isCurrentPlayer
            )
            self.finishExitMorphAfterSurfaceSettle()
        }
    }

    func setMode(
        _ mode: PlayerFullscreenMode?,
        trigger: VideoDetailFullscreenTrigger,
        animated: Bool,
        playerViewModel: PlayerStateViewModel?,
        isCurrentPlayer: PlayerCurrentPredicate? = nil
    ) {
        advanceStateRevision()
        let update = {
            self.mode = mode
            self.trigger = trigger
            if mode != nil || trigger == .rotation {
                self.isSystemRotationLayoutTransitioning = true
            }
        }

        if animated {
            withAnimation(Self.inlineTransitionAnimation, update)
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction, update)
        }
        refreshActivePlayerSurfaceLayout(
            playerViewModel: playerViewModel,
            coordinatedWithSwiftUILayout: true,
            isCurrentPlayer: isCurrentPlayer
        )
        if mode != nil || trigger == .rotation {
            scheduleRotationLayoutTransitionFallbackFinish(
                playerViewModel: playerViewModel,
                isCurrentPlayer: isCurrentPlayer
            )
        }
    }

    func canRefreshSurface(
        for playerViewModel: PlayerStateViewModel?,
        isCurrentPlayer: PlayerCurrentPredicate?
    ) -> Bool {
        guard let playerViewModel, !playerViewModel.isTerminated else { return false }
        guard let isCurrentPlayer else { return true }
        return isCurrentPlayer(playerViewModel)
    }

    func scheduleRotationLayoutTransitionFallbackFinish(
        playerViewModel: PlayerStateViewModel?,
        isCurrentPlayer: PlayerCurrentPredicate?
    ) {
        guard isSystemRotationLayoutTransitioning else { return }
        cancelPendingRotationLayoutTransitionFinishTask(advancesGeneration: false)
        let generation = advanceRotationLayoutTransitionGeneration()
        pendingRotationLayoutTransitionFinishTask = Task { @MainActor [weak self, weak playerViewModel, isCurrentPlayer] in
            defer {
                self?.clearPendingRotationLayoutTransitionFinishTaskIfCurrent(generation: generation)
            }
            try? await Task.sleep(nanoseconds: Self.rotationLayoutTransitionFallbackNanoseconds)
            guard let self,
                  !Task.isCancelled,
                  self.rotationLayoutTransitionGeneration == generation,
                  self.isSystemRotationLayoutTransitioning
            else { return }

            self.isSystemRotationLayoutTransitioning = false
            self.refreshActivePlayerSurfaceLayout(
                playerViewModel: playerViewModel,
                coordinatedWithSwiftUILayout: true,
                isCurrentPlayer: isCurrentPlayer
            )
            self.finishExitMorphAfterSurfaceSettle()
        }
    }
}
