import Foundation

@MainActor
struct VideoDetailPlaybackScenePlaybackLoadActions {
    let viewModel: VideoDetailViewModel

    func retryPlaybackLoad() {
        guard canRetryPlaybackLoad else { return }
        Task { @MainActor [weak viewModel] in
            guard let viewModel,
                  !viewModel.isPlaybackInvalidatedForNavigation
            else { return }
            await viewModel.load()
        }
    }

    private var canRetryPlaybackLoad: Bool {
        !viewModel.isPlaybackInvalidatedForNavigation
    }
}
