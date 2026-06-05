import Combine

@MainActor
final class VideoDetailViewModelHolder: ObservableObject {
    @Published var viewModel: VideoDetailViewModel?
    private var cancellable: AnyCancellable?
    private var snapshotRefreshTask: Task<Void, Never>?
    private var cleanupPlayback: (() -> Void)?
    private var lastSnapshot: VideoDetailRenderSnapshot?

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
            lastSnapshot = VideoDetailRenderSnapshot(viewModel)
            cancellable = Publishers.CombineLatest3(
                viewModel.$detail
                    .map(VideoDetailSnapshotSignature.init)
                    .removeDuplicates(),
                viewModel.$selectedCID
                    .removeDuplicates(),
                viewModel.$state
                    .removeDuplicates()
            )
            .dropFirst()
            .sink { [weak self] _, _, _ in
                self?.scheduleSnapshotRefresh(for: viewModel)
            }
        }
    }

    private func scheduleSnapshotRefresh(for viewModel: VideoDetailViewModel) {
        guard snapshotRefreshTask == nil else { return }
        snapshotRefreshTask = Task { @MainActor [weak self, weak viewModel] in
            try? await Task.sleep(nanoseconds: 16_000_000)
            guard let self, let viewModel, !Task.isCancelled else { return }
            self.snapshotRefreshTask = nil
            let snapshot = VideoDetailRenderSnapshot(viewModel)
            guard snapshot != self.lastSnapshot else { return }
            self.lastSnapshot = snapshot
            self.objectWillChange.send()
        }
    }

    deinit {
        cleanupPlayback?()
        snapshotRefreshTask?.cancel()
    }
}

private struct VideoDetailRenderSnapshot: Equatable {
    let detailSignature: VideoDetailSnapshotSignature
    let selectedCID: Int?
    let state: LoadingState

    init(_ viewModel: VideoDetailViewModel) {
        detailSignature = VideoDetailSnapshotSignature(viewModel.detail)
        selectedCID = viewModel.selectedCID
        state = viewModel.state
    }
}

private struct VideoDetailSnapshotSignature: Equatable {
    let bvid: String
    let aid: Int
    let cid: Int
    let title: String
    let description: String
    let ownerSignature: String
    let statSignature: String
    let pageSignature: String
    let aspectRatioBits: UInt64
    let pubdate: Int
    let duration: Int

    init(_ video: VideoItem) {
        let owner = video.owner
        let stat = video.stat
        let pages = video.pages ?? []
        bvid = video.bvid
        aid = video.aid ?? 0
        cid = video.cid ?? 0
        title = video.title
        description = video.desc ?? ""
        ownerSignature = [
            String(owner?.mid ?? 0),
            owner?.name ?? "",
            owner?.face ?? ""
        ].joined(separator: "|")
        statSignature = [
            String(stat?.view ?? 0),
            String(stat?.reply ?? 0),
            String(stat?.like ?? 0),
            String(stat?.coin ?? 0),
            String(stat?.favorite ?? 0)
        ].joined(separator: "|")
        pageSignature = pages.map(Self.pageSignature(for:)).joined(separator: "|")
        aspectRatioBits = (video.dimension?.aspectRatio ?? 0).bitPattern
        pubdate = video.pubdate ?? 0
        duration = video.duration ?? 0
    }

    nonisolated private static func pageSignature(for page: VideoPage) -> String {
        [
            String(page.cid),
            page.part ?? "",
            String(page.dimension?.width ?? 0),
            String(page.dimension?.height ?? 0)
        ].joined(separator: ":")
    }
}
