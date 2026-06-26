import Foundation

private enum VideoDetailPinnedHeaderSurfaceRefreshSchedule {
    static let coordinatedDelays: [UInt64] = [
        16_000_000,
        50_000_000,
        120_000_000
    ]
}

final class VideoDetailPinnedDynamicPlayerHeaderSurfaceRefreshCoordinator {
    private var pendingTask: Task<Void, Never>?
    private var needsReschedule = false
    private var refreshGeneration = 0

    @MainActor
    func schedule(playerIdentityStore: VideoDetailPlayerIdentityRenderStore) {
        guard let playerViewModel = playerIdentityStore.playerViewModel else {
            cancelPendingRefreshTask()
            return
        }
        let identityRevision = playerIdentityStore.revision
        guard canRefreshSurface(
            playerViewModel,
            playerIdentityStore: playerIdentityStore,
            identityRevision: identityRevision
        ) else {
            cancelPendingRefreshTask()
            return
        }
        guard pendingTask == nil else {
            needsReschedule = true
            return
        }
        needsReschedule = false
        let refreshGeneration = advanceRefreshGeneration()
        pendingTask = Task { @MainActor [weak self, weak playerIdentityStore, weak playerViewModel] in
            defer {
                self?.clearPendingRefreshTaskIfCurrent(generation: refreshGeneration)
            }
            await Task.yield()
            guard let self,
                  let playerViewModel,
                  !Task.isCancelled,
                  self.refreshGeneration == refreshGeneration,
                  self.canRefreshSurface(
                    playerViewModel,
                    playerIdentityStore: playerIdentityStore,
                    identityRevision: identityRevision
                  )
            else { return }
            playerViewModel.refreshSurfaceLayout()

            for delay in VideoDetailPinnedHeaderSurfaceRefreshSchedule.coordinatedDelays {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled,
                      self.refreshGeneration == refreshGeneration,
                      self.canRefreshSurface(
                        playerViewModel,
                        playerIdentityStore: playerIdentityStore,
                        identityRevision: identityRevision
                      )
                else { return }
                playerViewModel.refreshSurfaceLayout()
            }

            guard self.refreshGeneration == refreshGeneration,
                  self.needsReschedule,
                  let playerIdentityStore
            else {
                self.needsReschedule = false
                return
            }
            self.needsReschedule = false
            self.clearPendingRefreshTaskIfCurrent(generation: refreshGeneration)
            if self.canRefreshSurface(
                playerViewModel,
                playerIdentityStore: playerIdentityStore,
                identityRevision: identityRevision
            ) {
                self.schedule(playerIdentityStore: playerIdentityStore)
            }
        }
    }

    @MainActor
    func cancel() {
        cancelPendingRefreshTask()
    }

    @discardableResult
    private func advanceRefreshGeneration() -> Int {
        refreshGeneration += 1
        return refreshGeneration
    }

    private func cancelPendingRefreshTask(advancesGeneration: Bool = true) {
        pendingTask?.cancel()
        pendingTask = nil
        needsReschedule = false
        if advancesGeneration {
            advanceRefreshGeneration()
        }
    }

    private func clearPendingRefreshTaskIfCurrent(generation: Int) {
        guard refreshGeneration == generation else { return }
        pendingTask = nil
    }

    @MainActor
    private func canRefreshSurface(
        _ playerViewModel: PlayerStateViewModel,
        playerIdentityStore: VideoDetailPlayerIdentityRenderStore?,
        identityRevision: Int
    ) -> Bool {
        guard let playerIdentityStore else { return false }
        guard playerIdentityStore.revision == identityRevision else { return false }
        guard playerIdentityStore.playerViewModel === playerViewModel else { return false }
        guard !playerViewModel.isTerminated else { return false }
        return ActivePlaybackCoordinator.shared.isActive(playerViewModel)
    }

    deinit {
        pendingTask?.cancel()
    }
}
