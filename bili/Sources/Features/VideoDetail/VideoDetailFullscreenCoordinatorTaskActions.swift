import Foundation

extension VideoDetailFullscreenCoordinator {
    @discardableResult
    func advanceFullscreenTransitionGeneration() -> Int {
        fullscreenTransitionGeneration += 1
        return fullscreenTransitionGeneration
    }

    @discardableResult
    func advanceSurfaceLayoutRefreshGeneration() -> Int {
        surfaceLayoutRefreshGeneration += 1
        return surfaceLayoutRefreshGeneration
    }

    @discardableResult
    func advanceRotationLayoutTransitionGeneration() -> Int {
        rotationLayoutTransitionGeneration += 1
        return rotationLayoutTransitionGeneration
    }

    @discardableResult
    func advanceMorphTransitionGeneration() -> Int {
        morphTransitionGeneration += 1
        return morphTransitionGeneration
    }

    @discardableResult
    func advanceStateRevision() -> Int {
        stateRevision += 1
        return stateRevision
    }

    func cancelPendingFullscreenExitTask(advancesGeneration: Bool = true) {
        pendingFullscreenExitTask?.cancel()
        pendingFullscreenExitTask = nil
        if advancesGeneration {
            advanceFullscreenTransitionGeneration()
        }
    }

    func cancelPendingSurfaceLayoutRefreshTask(advancesGeneration: Bool = true) {
        pendingSurfaceLayoutRefreshTask?.cancel()
        pendingSurfaceLayoutRefreshTask = nil
        if advancesGeneration {
            advanceSurfaceLayoutRefreshGeneration()
        }
    }

    func cancelPendingRotationLayoutTransitionFinishTask(advancesGeneration: Bool = true) {
        pendingRotationLayoutTransitionFinishTask?.cancel()
        pendingRotationLayoutTransitionFinishTask = nil
        if advancesGeneration {
            advanceRotationLayoutTransitionGeneration()
        }
    }

    func cancelPendingPortraitExitSurfaceSettleTask(advancesGeneration: Bool = true) {
        pendingPortraitExitSurfaceSettleTask?.cancel()
        pendingPortraitExitSurfaceSettleTask = nil
        if advancesGeneration {
            advanceRotationLayoutTransitionGeneration()
        }
    }

    func cancelPendingMorphTransitionTask(advancesGeneration: Bool = true) {
        pendingMorphTransitionTask?.cancel()
        pendingMorphTransitionTask = nil
        if advancesGeneration {
            advanceMorphTransitionGeneration()
        }
    }

    func clearPendingFullscreenExitTaskIfCurrent(generation: Int) {
        guard fullscreenTransitionGeneration == generation else { return }
        pendingFullscreenExitTask = nil
    }

    func clearPendingSurfaceLayoutRefreshTaskIfCurrent(generation: Int) {
        guard surfaceLayoutRefreshGeneration == generation else { return }
        pendingSurfaceLayoutRefreshTask = nil
    }

    func clearPendingRotationLayoutTransitionFinishTaskIfCurrent(generation: Int) {
        guard rotationLayoutTransitionGeneration == generation else { return }
        pendingRotationLayoutTransitionFinishTask = nil
    }

    func clearPendingPortraitExitSurfaceSettleTaskIfCurrent(generation: Int) {
        guard rotationLayoutTransitionGeneration == generation else { return }
        pendingPortraitExitSurfaceSettleTask = nil
    }

    func clearPendingMorphTransitionTaskIfCurrent(generation: Int) {
        guard morphTransitionGeneration == generation else { return }
        pendingMorphTransitionTask = nil
    }

    func isCurrentStateRevision(_ revision: Int) -> Bool {
        stateRevision == revision
    }
}
