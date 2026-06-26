import Foundation

extension VideoDetailViewModel {
    func warmCachedPlayInfoIfAvailable() {
        guard let cid = selectedCID, selectedPlayVariant == nil else { return }
        let bvid = detail.bvid
        let page = selectedPageNumber
        trackBackgroundTask(
            Task(priority: .userInitiated) { [weak self] in
                guard let self else { return }
                if let data = await VideoPreloadCenter.shared.cachedOrPendingPlayURL(
                    for: bvid,
                    cid: cid,
                    page: page,
                    waitsForPending: false,
                    preferredQuality: self.adaptiveStartupPreferredQuality
                ) {
                    guard self.isCurrentPlaybackContext(bvid: bvid, cid: cid, page: page),
                          self.selectedPlayVariant == nil
                    else { return }
                    await self.applyPlayURLData(
                        data,
                        cid: cid,
                        page: page,
                        source: "detailWarmCache",
                        schedulesSupplementalLoad: false
                    )
                }
            }
        )
    }

    func applyPlayURLData(
        _ data: PlayURLData,
        cid: Int?,
        page: Int?,
        source: String = "unknown",
        schedulesSupplementalLoad: Bool = true
    ) async {
        let bvid = detail.bvid
        guard isCurrentPlaybackContext(bvid: bvid, cid: cid, page: page) else { return }
        let variants = sortedPlayVariants(data.playVariants(cdnPreference: libraryStore.effectivePlaybackCDNPreference))
        guard let appliedState = applyPlayableVariantState(variants: variants, source: source) else { return }
        guard isCurrentPlaybackContext(bvid: bvid, cid: cid, page: page) else { return }
        if stablePlayerViewModel == nil {
            guard isCurrentPlaybackContext(bvid: bvid, cid: cid, page: page)
            else {
                return
            }
        }
        await schedulePostPlayURLApplicationWork(
            variants: variants,
            selectedVariant: appliedState.selectedVariant,
            targetVariant: appliedState.targetVariant,
            cid: cid,
            page: page,
            schedulesSupplementalLoad: schedulesSupplementalLoad
        )
    }

    func isPlayablePlayURLData(_ data: PlayURLData) -> Bool {
        data.playVariants(cdnPreference: libraryStore.effectivePlaybackCDNPreference)
            .contains(where: \.isPlayable)
    }
}
