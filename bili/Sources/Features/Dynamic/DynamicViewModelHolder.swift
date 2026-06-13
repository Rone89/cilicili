import Combine

@MainActor
final class DynamicViewModelHolder: ObservableObject {
    @Published var viewModel: DynamicViewModel?
    private var cancellable: AnyCancellable?
    private var snapshotRefreshTask: Task<Void, Never>?
    private var lastSnapshot: DynamicRenderSnapshot?

    func configure(api: BiliAPIClient, libraryStore: LibraryStore, sessionStore: SessionStore) {
        if viewModel == nil {
            let viewModel = DynamicViewModel(api: api, libraryStore: libraryStore, sessionStore: sessionStore)
            self.viewModel = viewModel
            lastSnapshot = DynamicRenderSnapshot(viewModel)
            cancellable = viewModel.objectWillChange.sink { [weak self] _ in
                self?.scheduleSnapshotRefresh(for: viewModel)
            }
        }
    }

    private func scheduleSnapshotRefresh(for viewModel: DynamicViewModel) {
        guard snapshotRefreshTask == nil else { return }
        snapshotRefreshTask = Task { @MainActor [weak self, weak viewModel] in
            try? await Task.sleep(nanoseconds: 16_000_000)
            guard let self, let viewModel, !Task.isCancelled else { return }
            self.snapshotRefreshTask = nil
            let snapshot = DynamicRenderSnapshot(viewModel)
            guard snapshot != self.lastSnapshot else { return }
            self.lastSnapshot = snapshot
            self.objectWillChange.send()
        }
    }

    deinit {
        snapshotRefreshTask?.cancel()
    }
}

private struct DynamicRenderSnapshot: Equatable {
    let state: LoadingState
    let hasMoreItems: Bool
    let followedLiveRoomsRevision: Int
    let itemCount: Int
    let firstItemID: String?
    let lastItemID: String?
    let itemsRevision: Int

    init(_ viewModel: DynamicViewModel) {
        state = viewModel.state
        hasMoreItems = viewModel.hasMoreItems
        followedLiveRoomsRevision = viewModel.followedLiveRoomsRevision
        itemCount = viewModel.items.count
        firstItemID = viewModel.items.first?.id
        lastItemID = viewModel.items.last?.id
        itemsRevision = viewModel.itemsRevision
    }
}
