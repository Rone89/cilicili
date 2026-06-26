import Foundation

extension VideoDetailViewModel {
    func makeStablePlayerViewModel(
        variant: PlayVariant,
        alternateVideoRenditions: [PlayerVideoRenditionSource],
        resumeTime: TimeInterval
    ) -> PlayerStateViewModel {
        PlayerStateViewModel(
            videoURL: variant.videoURL,
            audioURL: variant.audioURL,
            videoStream: variant.videoStream,
            audioStream: variant.audioStream,
            alternateVideoRenditions: alternateVideoRenditions,
            title: detail.title,
            referer: "https://www.bilibili.com/video/\(detail.bvid)",
            durationHint: detail.duration.map(TimeInterval.init),
            resumeTime: resumeTime,
            startupResumePolicy: resumeTime > 0.25 ? .immediate : .deferred,
            dynamicRange: variant.dynamicRange,
            cdnPreference: libraryStore.effectivePlaybackCDNPreference,
            metricsID: detail.bvid
        )
    }

    func configureStablePlayerStartupCallbacks(_ playerViewModel: PlayerStateViewModel) {
        playerViewModel.restoreUserInterfaceForPictureInPictureStop = { [weak self, weak playerViewModel] in
            guard let self,
                  let playerViewModel,
                  self.stablePlayerViewModel === playerViewModel
            else { return false }
            return await PictureInPictureRestoreCoordinator.shared.restorePlaybackUI(for: self.detail)
        }
        playerViewModel.onPlaybackFailureWithReason = { [weak self, weak playerViewModel] message, reason in
            guard let self,
                  let playerViewModel,
                  self.stablePlayerViewModel === playerViewModel,
                  let variant = self.selectedPlayVariant
            else { return }
            self.finishPlaybackStartupWaiters(with: .failed)
            self.handlePlaybackError(
                message ?? PlayerEngineError.unsupportedMedia.localizedDescription,
                reason: reason,
                for: variant
            )
        }
        playerViewModel.onBufferingPressure = { [weak self, weak playerViewModel] count in
            guard let self,
                  let playerViewModel,
                  self.stablePlayerViewModel === playerViewModel
            else { return }
            self.handleBufferingPressure(count)
        }
        playerViewModel.onFirstFramePresented = { [weak self, weak playerViewModel] in
            guard let self,
                  let playerViewModel,
                  self.stablePlayerViewModel === playerViewModel
            else { return }
            self.finishPlaybackStartupWaiters(with: .firstFrame)
            self.releasePlaybackTransitionPlayer(after: Self.playbackTransitionReleaseDelayNanoseconds)
        }
    }
}
