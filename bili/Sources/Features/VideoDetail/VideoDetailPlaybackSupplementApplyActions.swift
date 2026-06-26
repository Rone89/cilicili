import Foundation

extension VideoDetailViewModel {
    func applySupplementalPlayURLData(
        _ data: PlayURLData,
        bvid: String,
        cid: Int,
        page: Int?,
        supplementStart: CFTimeInterval
    ) {
        guard !isPlaybackInvalidatedForNavigation,
              detail.bvid == bvid,
              selectedCID == cid
        else { return }
        let variants = data.playVariants(cdnPreference: libraryStore.effectivePlaybackCDNPreference)
        let supplementMilliseconds = formatMilliseconds(elapsedMilliseconds(since: supplementStart))
        guard !variants.isEmpty else {
            PlayerMetricsLog.record(
                .qualitySupplement,
                metricsID: detail.bvid,
                title: detail.title,
                message: "empty \(supplementMilliseconds)"
            )
            return
        }

        let currentVariant = selectedPlayVariant
        playVariants = mergedSupplementalVariants(
            variants,
            preserving: currentVariant
        )
        if shouldAutoUpgradeSupplementalVariant(from: currentVariant),
           let preferredVariant = preferredDefaultVariant(in: playVariants),
           preferredVariant.id != currentVariant?.id,
           let currentVariant {
            selectedPlayVariant = preferredVariant
            playbackFallbackMessage = nil
            if switchPlayVariantInPlaceIfPossible(preferredVariant) == false {
                updateStablePlayerViewModelIfNeeded(preservesPreviousPlayerUntilFirstFrame: true)
            }
            PlayerMetricsLog.record(
                .qualitySupplement,
                metricsID: detail.bvid,
                title: detail.title,
                message: "success \(supplementMilliseconds) autoDefault q\(currentVariant.quality)->q\(preferredVariant.quality) variants=\(variants.filter(\.isPlayable).count)"
            )
        } else if let currentVariant,
                  let matchingVariant = playVariants.first(where: { $0.id == currentVariant.id }) {
            selectedPlayVariant = matchingVariant
            PlayerMetricsLog.record(
                .qualitySupplement,
                metricsID: detail.bvid,
                title: detail.title,
                message: "success \(supplementMilliseconds) keep q\(matchingVariant.quality) variants=\(variants.filter(\.isPlayable).count)"
            )
        } else {
            selectedPlayVariant = preferredDefaultVariant(in: playVariants)
            PlayerMetricsLog.record(
                .qualitySupplement,
                metricsID: detail.bvid,
                title: detail.title,
                message: "success \(supplementMilliseconds) selected q\(selectedPlayVariant?.quality ?? 0) variants=\(variants.filter(\.isPlayable).count)"
            )
            updateStablePlayerViewModelIfNeeded()
        }
        if playbackAdaptationProfile.shouldWarmSupplementalVariants,
           !PlaybackEnvironment.current.shouldPreferConservativePlayback {
            warmLikelySupplementalVariantAfterFirstFrame(cid: cid, page: page)
        }
    }
}
