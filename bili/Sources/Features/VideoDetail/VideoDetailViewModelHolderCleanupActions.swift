import Foundation

@MainActor
struct VideoDetailViewModelHolderCleanupActions {
    let viewModel: VideoDetailViewModel

    func makeCleanupPlayback() -> () -> Void {
        { [weak viewModel] in
            guard let viewModel else { return }
            Task { @MainActor [weak viewModel] in
                viewModel?.stopPlaybackForNavigation()
            }
        }
    }
}
