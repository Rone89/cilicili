import Foundation

extension VideoDetailViewModel {
    func canPerformStagedStartupUpgrade(from startupVariantID: String, bvid: String, cid: Int) -> Bool {
        guard !isPlaybackInvalidatedForNavigation,
              !didSelectPlayVariantManually,
              detail.bvid == bvid,
              selectedCID == cid,
              selectedPlayVariant?.id == startupVariantID,
              !isSwitchingPlayQuality,
              playVariantSwitchTask == nil,
              let player = stablePlayerViewModel,
              player.hasPresentedPlayback,
              player.errorMessage == nil,
              !player.isBuffering,
              !player.isUserSeeking,
              !player.isPictureInPictureActive
        else { return false }
        if let lastUserSeekAt,
           Date().timeIntervalSince(lastUserSeekAt) < Self.fastStartUpgradeSeekCooldown {
            return false
        }
        if let playerLastUserSeekAt = player.lastUserSeekAt,
           Date().timeIntervalSince(playerLastUserSeekAt) < Self.fastStartUpgradeSeekCooldown {
            return false
        }
        return player.isPlaying || player.wantsAutoplay || currentPlaybackIntent()
    }

    func canPerformInPlaceHLSVariantUpgrade(from startupVariant: PlayVariant, to targetVariant: PlayVariant) -> Bool {
        guard startupVariant.audioURL != nil,
              startupVariant.audioURL == targetVariant.audioURL,
              let targetVideoURL = targetVariant.videoURL
        else { return false }
        return hlsAlternateVideoRenditions(for: startupVariant)
            .contains { $0.videoURL == targetVideoURL }
    }
}
