import Foundation

@MainActor
struct VideoDetailLoadedDetailContentPageActions {
    weak var viewModel: VideoDetailViewModel?

    func selectPage(_ page: VideoPage) {
        viewModel?.selectPage(page)
    }

    func retryRelated() async {
        guard let viewModel else { return }
        await viewModel.retryRelated()
    }
}
