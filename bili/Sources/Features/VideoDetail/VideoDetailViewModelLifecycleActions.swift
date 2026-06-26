import Combine
import Foundation

extension VideoDetailViewModel {
    func configureLifecycleBindings() {
        filterCancellable = libraryStore.$blocksGoodsComments
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                guard self?.isPlaybackInvalidatedForNavigation != true else { return }
                self?.refilterLoadedComments()
            }
        sponsorBlockCancellable = libraryStore.$sponsorBlockEnabled
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                guard self?.isPlaybackInvalidatedForNavigation != true else { return }
                self?.stablePlayerViewModel?.setSponsorBlockEnabled(isEnabled)
                if isEnabled {
                    self?.scheduleSponsorBlockSegmentsAfterFirstFrame()
                } else {
                    self?.resetSponsorBlockSegments()
                }
            }
        playbackAutoOptimizationCancellable = libraryStore.$playbackAutoOptimizationMode
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                guard self?.isPlaybackInvalidatedForNavigation != true else { return }
                self?.scheduleRenderStoreSync(.danmaku)
            }
        playbackPerformanceCancellable = PlayerPerformanceStore.shared.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard self?.isPlaybackInvalidatedForNavigation != true else { return }
                    self?.scheduleRenderStoreSync(.danmaku)
                }
            }
    }

}
