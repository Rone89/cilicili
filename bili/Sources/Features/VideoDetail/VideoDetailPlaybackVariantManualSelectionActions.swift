import Foundation

extension VideoDetailViewModel {
    func beginManualPlayVariantSelection(for variant: PlayVariant) -> UUID {
        let token = UUID()
        didSelectPlayVariantManually = true
        failedPlayVariantIDs.removeAll()
        playbackRecoveryAttemptCount = 0
        playbackRecoveryCoordinator.reset()
        lastBufferingCDNRefreshCount = 0
        libraryStore.setPreferredVideoQuality(variant.quality)
        cancelFastStartUpgradeTask()
        cancelPlayVariantSwitchTask()
        trackBackgroundTask(Task(priority: .utility) { [quality = variant.quality, cdnPreference = libraryStore.effectivePlaybackCDNPreference] in
            await VideoPreloadCenter.shared.updatePlaybackPreferences(
                preferredQuality: quality,
                targetPreferredQuality: quality,
                cdnPreference: cdnPreference,
                playbackAdaptationProfile: PlayerPlaybackAdaptationProfile(level: .normal)
            )
        })
        return token
    }

    func beginPlayVariantSwitch(for variant: PlayVariant, token: UUID) {
        playVariantSwitchToken = token
        isSwitchingPlayQuality = true
        pendingPlayVariantID = variant.id
    }
}
