import Foundation

extension VideoDetailViewModel {
    func cancelBackgroundWork() {
        cancelSupplementalWork()
        detailLoadingTask?.cancel()
        detailLoadingTask = nil
        detailLoadingToken = nil
    }

    func cancelSupplementalWork() {
        cancelBackgroundTasks()
        pageLoadingTask?.cancel()
        pageLoadingTask = nil
        pageLoadingToken = nil
        detailLoadingTask?.cancel()
        detailLoadingTask = nil
        detailLoadingToken = nil
        cancelPlayURLSupplementTask()
        cancelStartupPlayURLTask()
        cancelFastStartUpgradeTask()
        cancelHLSRenditionPrebuildTask()
        cancelSeekWarmups(clearRecent: true)
        isSupplementingPlayQualities = false
        cancelPlayVariantSwitchTask()
        cancelRelatedPreloadTask()
        cancelRelatedArtworkPrefetchTask()
        cancelRelatedRefreshTask()
        cancelUploaderInteractionTask()
        uploaderInteractionLoadIdentity = nil
        finishPlaybackStartupWaiters(with: nil)
    }

    nonisolated static func cancelMediaWarmupsPreservingCache() {
        Task(priority: .utility) {
            await VideoPreloadCenter.shared.cancelMediaWarmups(clearCache: false)
        }
    }
}
