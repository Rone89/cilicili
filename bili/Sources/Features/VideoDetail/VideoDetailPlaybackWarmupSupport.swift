import Foundation

extension VideoDetailViewModel {
    func shouldUseStagedStartupVariant(for targetVariant: PlayVariant) -> Bool {
        stagedStartupDisabledReason(for: targetVariant) == nil
    }

    func stagedStartupDisabledReason(for targetVariant: PlayVariant) -> String? {
        guard !didSelectPlayVariantManually else { return "manualSelection" }
        guard targetVariant.isPlayable else { return "notPlayable" }
        guard !targetVariant.isProgressiveFastStart else { return "progressive" }
        guard targetVariant.audioURL != nil else { return "noAudio" }
        guard targetVariant.videoStream?.isHardwareDecodingCompatibleVideo == true else { return "unsupportedCodec" }
        guard targetVariant.dynamicRange == .sdr else { return "dynamicRange-\(targetVariant.dynamicRange.rawValue)" }
        guard targetVariant.quality >= 74 else { return "lowTargetQuality" }
        let environment = PlaybackEnvironment.current
        guard !environment.shouldPreferConservativePlayback else { return "conservative" }
        switch environment.networkClass {
        case .wifi, .unknown:
            break
        case .cellular, .constrained:
            return "network-\(environment.networkClass.performanceSampleKey)"
        }

        return nil
    }

    func shouldScheduleStagedStartupUpgrade(from startupVariant: PlayVariant, to targetVariant: PlayVariant) -> Bool {
        guard shouldUseStagedStartupVariant(for: targetVariant),
              startupVariant.isPlayable,
              targetVariant.isPlayable,
              startupVariant.id != targetVariant.id,
              variant(targetVariant, isBetterThan: startupVariant)
        else { return false }
        return true
    }
}
