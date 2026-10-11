import Foundation

extension VideoDetailViewModel {
    func schedulePgcPlaybackSigningKeyWarmup() {
        guard detail.isPGCEpisode, playbackOptions.usesStartupCaches,
              !isPlaybackInvalidatedForNavigation else { return }
        // Signing does not need CID. Overlap it with season resolution without
        // waiting for it before displaying the selected episode's information.
        trackBackgroundTask(Task(priority: .userInitiated) { [api] in
            guard !Task.isCancelled else { return }
            await api.prewarmPlaybackSigningKeys(priority: URLSessionTask.highPriority)
        })
    }

    func scheduleDetailAndPlaybackPreloadIfMissingCID(priority: TaskPriority = .utility) {
        guard playbackOptions.usesStartupCaches,
              !detail.isPGCEpisode,
              !isPlaybackInvalidatedForNavigation,
              selectedCID == nil,
              !detail.bvid.isEmpty
        else { return }
        let seedDetail = detail
        let preferredQuality = adaptiveStartupPreferredQuality
        let targetPreferredQuality = targetPlaybackPreferredQuality
        let cdnPreference = libraryStore.effectivePlaybackCDNPreference
        let adaptationProfile = playbackAdaptationProfile
        trackBackgroundTask(
            Task(priority: priority) { [api] in
                guard !Task.isCancelled else { return }
                await VideoPreloadCenter.shared.prioritizePlayback(for: seedDetail)
                guard !Task.isCancelled else { return }
                await VideoPreloadCenter.shared.preloadDetailAndPlayback(
                    seedDetail,
                    api: api,
                    preferredQuality: preferredQuality,
                    targetPreferredQuality: targetPreferredQuality,
                    cdnPreference: cdnPreference,
                    warmsMedia: true,
                    mediaWarmupDelay: 0.15,
                    priority: priority,
                    playbackAdaptationProfile: adaptationProfile
                )
            }
        )
    }
}
