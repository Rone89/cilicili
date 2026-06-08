import Combine

@MainActor
final class VideoDetailViewModelHolder: ObservableObject {
    @Published var viewModel: VideoDetailViewModel?
    private var cleanupPlayback: (() -> Void)?

    func configure(
        seedVideo: VideoItem,
        api: BiliAPIClient,
        libraryStore: LibraryStore,
        sponsorBlockService: SponsorBlockService
    ) {
        if viewModel == nil {
            let viewModel = VideoDetailViewModel(
                seedVideo: seedVideo,
                api: api,
                libraryStore: libraryStore,
                sponsorBlockService: sponsorBlockService
            )
            self.viewModel = viewModel
            cleanupPlayback = { [weak viewModel] in
                Task { @MainActor [weak viewModel] in
                    viewModel?.stopPlaybackForNavigation()
                }
            }
        }
    }

    deinit {
        cleanupPlayback?()
    }
}
