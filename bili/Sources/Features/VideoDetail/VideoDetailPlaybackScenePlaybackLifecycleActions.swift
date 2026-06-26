import Foundation

@MainActor
struct VideoDetailPlaybackScenePlaybackLifecycleActions {
    let viewModel: VideoDetailViewModel
    let isClosingDetail: () -> Bool
    let markClosingDetail: () -> Void

    private var shouldTreatAsClosingDetail: Bool {
        isClosingDetail()
            || viewModel.isPlaybackTerminatedForNavigation
            || viewModel.isPlaybackInvalidatedForNavigation
    }

    func handleNavigationTransitionCompleted(_ cancelled: Bool) {
        cancelled
            ? resumeAfterCancelledNavigationTransition()
            : stopAfterCompletedNavigationTransition()
    }

    func pausePlaybackForPotentialNavigation() {
        guard !shouldTreatAsClosingDetail else { return }
        viewModel.pausePlaybackForPotentialNavigation()
    }

    func stopPlaybackForNavigation() {
        guard !viewModel.isPlaybackInvalidatedForNavigation else { return }
        viewModel.stopPlaybackForNavigation()
    }

    func stopOrPausePlaybackForDisappear() {
        if shouldTreatAsClosingDetail {
            viewModel.stopPlaybackForNavigation()
        } else {
            viewModel.pausePlaybackForPotentialNavigation()
        }
    }

    func resumePlaybackAfterCoveredNavigationIfNeeded() {
        guard !shouldTreatAsClosingDetail else { return }
        viewModel.resumePlaybackAfterCoveredNavigationIfNeeded()
    }

    func resumePlaybackAfterCancelledNavigation() {
        guard !shouldTreatAsClosingDetail else { return }
        viewModel.resumePlaybackAfterCancelledNavigation()
    }

    private func resumeAfterCancelledNavigationTransition() {
        guard !shouldTreatAsClosingDetail else { return }
        viewModel.resumePlaybackAfterCancelledNavigation()
    }

    private func stopAfterCompletedNavigationTransition() {
        if !shouldTreatAsClosingDetail {
            markClosingDetail()
        }
        viewModel.stopPlaybackForNavigation()
    }
}
