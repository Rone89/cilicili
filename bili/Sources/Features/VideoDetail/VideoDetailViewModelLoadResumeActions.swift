import Foundation

extension VideoDetailViewModel {
    func resumeLoadedDetailIfNeeded() async {
        guard !isPlaybackInvalidatedForNavigation else { return }
        scheduleDanmakuLoadIfNeeded()
        scheduleRelatedLoadIfNeeded()
        scheduleUploaderAndInteractionLoadIfNeeded()
        guard stablePlayerViewModel == nil else { return }

        if selectedPlayVariant?.isPlayable == true {
            restoreStablePlayerForLoadedDetail()
        } else {
            await loadPlayURLIfNeeded()
        }
    }

    func restoreStablePlayerForLoadedDetail() {
        let resumeTime = pendingNavigationResumeTime
        let shouldResumeOverride: Bool? = shouldResumePlaybackAfterCancelledNavigation
            ? true
            : (hasPendingNavigationInterruption ? false : nil)
        guard !isPlaybackInvalidatedForNavigation else { return }
        updateStablePlayerViewModelIfNeeded(
            resumeTimeOverride: resumeTime,
            shouldResumePlayback: shouldResumeOverride
        )
        pendingNavigationResumeTime = nil
        shouldResumePlaybackAfterCancelledNavigation = false
        hasPendingNavigationInterruption = false
    }

    func schedulePlaybackStartupSideLoads() {
        schedulePlayURLLoadIfNeeded()
        scheduleUploaderAndInteractionLoadIfNeeded()
        scheduleFullDetailLoadIfNeeded(priority: .utility, waitsForFirstFrame: true)
    }

    func startPlaybackAfterFastStartActivation() async {
        await prioritizeCurrentPlaybackForStartup()
        scheduleUploaderAndInteractionLoadIfNeeded()
        scheduleFullDetailLoadIfNeeded(priority: .utility, waitsForFirstFrame: true)
        await loadPlayURLIfNeeded()
    }
}
