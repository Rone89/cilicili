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
                    if self.shouldSkipWarmCacheForTargetQuality(data) {
                        self.logPlayURLCacheBypass(kind: "WarmCacheTargetMiss", data: data)
                        return
                    }
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

    private func shouldSkipWarmCacheForTargetQuality(_ data: PlayURLData) -> Bool {
        guard let preferredQuality = targetPlaybackPreferredQuality else { return false }
        let variants = data.playVariants(cdnPreference: libraryStore.effectivePlaybackCDNPreference)
        return !variants.contains {
            $0.isPlayable
                && $0.quality == preferredQuality
                && (![116, 74].contains(preferredQuality) || variantFrameRate($0) >= 50)
        }
    }
}
