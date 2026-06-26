import Foundation

extension VideoDetailViewModel {
    func prepareAutomaticCDNRecommendationForPlayback() async {
        let previousCDNPreference = libraryStore.effectivePlaybackCDNPreference
        await PlayerMetricsLog.withSignpostedInterval(
            "VideoDetailCDNRecommendation",
            message: "bvid=\(detail.bvid) preference=\(previousCDNPreference.rawValue)"
        ) {
            await PlaybackCDNProbeCoordinator.shared.prepareRecommendationForImmediatePlaybackIfNeeded(
                libraryStore: libraryStore,
                timeout: cdnRecommendationStartupBudget
            )
        }
        let updatedCDNPreference = libraryStore.effectivePlaybackCDNPreference
        guard updatedCDNPreference != previousCDNPreference,
              updatedCDNPreference != .automatic
        else { return }
        PlayerMetricsLog.record(
            .network,
            metricsID: detail.bvid,
            title: detail.title,
            message: "cdnStartupRecommendation=\(updatedCDNPreference.title)"
        )
    }

    func scheduleAutomaticCDNRecommendationForPlayback() {
        guard libraryStore.playbackCDNPreference == .automatic else { return }
        PlaybackCDNProbeCoordinator.shared.refreshIfNeeded(libraryStore: libraryStore)
    }

    func scheduleAutomaticCDNRecommendationAfterFirstFrameIfNeeded(cid: Int?, page: Int?) {
        guard libraryStore.playbackCDNPreference == .automatic,
              let cid,
              !isPlaybackInvalidatedForNavigation
        else { return }

        let bvid = detail.bvid
        trackBackgroundTask(
            Task(priority: .utility) { [weak self] in
                guard let self else { return }
                let didPresentPlayback = await self.waitForFirstFrameOrFailure()
                guard didPresentPlayback,
                      !Task.isCancelled,
                      !self.isPlaybackInvalidatedForNavigation,
                      self.detail.bvid == bvid,
                      self.selectedCID == cid,
                      self.selectedPageNumber == page,
                      self.libraryStore.playbackCDNPreference == .automatic
                else { return }

                PlayerMetricsLog.signpostEvent(
                    "VideoDetailCDNRecommendation",
                    message: "postFirstFrame bvid=\(bvid) cid=\(cid)"
                )
                PlaybackCDNProbeCoordinator.shared.refreshIfNeeded(libraryStore: self.libraryStore)
            }
        )
    }
}
