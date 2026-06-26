import Foundation
import OSLog

extension VideoDetailViewModel {
    func selectPlayVariant(_ variant: PlayVariant) {
        guard !isPlaybackInvalidatedForNavigation, variant.isPlayable else { return }
        guard selectedPlayVariant?.id != variant.id else { return }
        let initialResumeTime = currentPlaybackResumeTime()
        let initialShouldResumePlayback = currentPlaybackIntent()
        let initialPlaybackRate = stablePlayerViewModel?.playbackRate ?? .x10
        let cid = selectedCID
        let token = beginManualPlayVariantSelection(for: variant)
        if switchPlayVariantInPlaceIfPossible(variant) {
            clearPlayVariantSwitchIfCurrent(token)
            return
        }
        beginPlayVariantSwitch(for: variant, token: token)
        schedulePlayVariantSwitchTask(
            to: variant,
            cid: cid,
            token: token,
            initialResumeTime: initialResumeTime,
            initialShouldResumePlayback: initialShouldResumePlayback,
            initialPlaybackRate: initialPlaybackRate
        )
    }

    func switchPlayVariantInPlaceIfPossible(_ variant: PlayVariant) -> Bool {
        guard let playerViewModel = stablePlayerViewModel,
              playerViewModel.engineDiagnostics.hlsVideoVariantCount > 1,
              playerViewModel.preferVideoRenditionInCurrentItem(variant)
        else { return false }

        selectedPlayVariant = variant
        stablePlayerIdentity = playerIdentity(for: variant)
        playbackFallbackMessage = nil
        observePlaybackErrors(playerViewModel, variant: variant)
        logSelectedPlayVariant(
            variant,
            availableVariants: playVariants,
            source: "manualInPlaceQuality"
        )
        PlayerMetricsLog.record(
            .qualitySupplement,
            metricsID: detail.bvid,
            title: detail.title,
            message: "manualInPlaceQuality q\(variant.quality)"
        )
        return true
    }

    func clearPlayVariantSwitchIfCurrent(_ token: UUID) {
        guard playVariantSwitchToken == token else { return }
        playVariantSwitchTask = nil
        playVariantSwitchToken = nil
        pendingPlayVariantID = nil
        isSwitchingPlayQuality = false
    }

}
