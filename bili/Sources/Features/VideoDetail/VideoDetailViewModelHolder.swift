import Combine
import Foundation

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
        guard viewModel == nil else { return }
        installViewModel(
            makeViewModel(
                seedVideo: seedVideo,
                api: api,
                libraryStore: libraryStore,
                sponsorBlockService: sponsorBlockService
            )
        )
    }

    deinit {
        cleanupPlayback?()
    }

    private func makeViewModel(
        seedVideo: VideoItem,
        api: BiliAPIClient,
        libraryStore: LibraryStore,
        sponsorBlockService: SponsorBlockService
    ) -> VideoDetailViewModel {
        VideoDetailViewModel(
            seedVideo: seedVideo,
            api: api,
            libraryStore: libraryStore,
            sponsorBlockService: sponsorBlockService
        )
    }

    private func installViewModel(_ viewModel: VideoDetailViewModel) {
        self.viewModel = viewModel
        cleanupPlayback = VideoDetailViewModelHolderCleanupActions(
            viewModel: viewModel
        )
        .makeCleanupPlayback()
    }
}
