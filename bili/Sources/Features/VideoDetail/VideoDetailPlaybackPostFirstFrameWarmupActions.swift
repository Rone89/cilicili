import Foundation

extension VideoDetailViewModel {
    func warmLikelySupplementalVariantAfterFirstFrame(cid: Int, page: Int?) {
        guard !isPlaybackInvalidatedForNavigation,
              playbackAdaptationProfile.shouldWarmSupplementalVariants,
              !PlaybackEnvironment.current.shouldPreferConservativePlayback
        else { return }
        let variants = supplementalWarmupVariants()
        guard !variants.isEmpty else { return }
        let bvid = detail.bvid
        trackBackgroundTask(
            Task(priority: .utility) { [weak self] in
                guard let self else { return }
                let didPresentPlayback = await self.waitForFirstFrameOrFailure()
                guard !self.isPlaybackInvalidatedForNavigation,
                      self.detail.bvid == bvid,
                      self.selectedCID == cid
                else { return }
                guard didPresentPlayback else { return }
                for (index, variant) in variants.prefix(1).enumerated() {
                    guard !Task.isCancelled,
                          !self.isPlaybackInvalidatedForNavigation,
                          self.detail.bvid == bvid,
                          self.selectedCID == cid
                    else { return }
                    await VideoPreloadCenter.shared.warmVariant(
                        variant,
                        bvid: bvid,
                        cid: cid,
                        page: page,
                        delay: index == 0 ? 0 : 0.45
                    )
                }
            }
        )
    }
}
