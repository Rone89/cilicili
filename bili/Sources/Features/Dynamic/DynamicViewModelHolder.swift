import Combine

@MainActor
final class DynamicViewModelHolder: ObservableObject {
    @Published var viewModel: DynamicViewModel?
    private var cancellable: AnyCancellable?
    private var snapshotRefreshTask: Task<Void, Never>?
    private var lastSnapshot: DynamicRenderSnapshot?
    private var viewModels: [DynamicFeedKind: DynamicViewModel] = [:]

    init(
        api: BiliAPIClient? = nil,
        libraryStore: LibraryStore? = nil,
        sessionStore: SessionStore? = nil
    ) {
        guard let api, let libraryStore, let sessionStore else { return }
        installViewModel(api: api, libraryStore: libraryStore, sessionStore: sessionStore)
    }

    func configure(api: BiliAPIClient, libraryStore: LibraryStore, sessionStore: SessionStore) {
        guard viewModel == nil else { return }
        installViewModel(api: api, libraryStore: libraryStore, sessionStore: sessionStore)
    }

    func reconfigure(api: BiliAPIClient, libraryStore: LibraryStore, sessionStore: SessionStore) {
        snapshotRefreshTask?.cancel()
        snapshotRefreshTask = nil
        cancellable = nil
        viewModel = nil
        lastSnapshot = nil
        viewModels.values.forEach { $0.invalidateAccount() }
        viewModels.removeAll()
        installViewModel(api: api, libraryStore: libraryStore, sessionStore: sessionStore)
    }

    func selectFeed(_ kind: DynamicFeedKind, api: BiliAPIClient, libraryStore: LibraryStore, sessionStore: SessionStore) {
        guard viewModel?.feedKind != kind else { return }
        snapshotRefreshTask?.cancel()
        snapshotRefreshTask = nil
        cancellable = nil
        let model = viewModels[kind] ?? DynamicViewModel(
            api: api, libraryStore: libraryStore, sessionStore: sessionStore, feedKind: kind
        )
        observe(model)
    }

    private func installViewModel(
        api: BiliAPIClient,
        libraryStore: LibraryStore,
        sessionStore: SessionStore
    ) {
        let viewModel = DynamicViewModel(api: api, libraryStore: libraryStore, sessionStore: sessionStore)
        observe(viewModel)
    }

    private func observe(_ viewModel: DynamicViewModel) {
        viewModels[viewModel.feedKind] = viewModel
        self.viewModel = viewModel
        lastSnapshot = DynamicRenderSnapshot(viewModel)
        cancellable = viewModel.objectWillChange.sink { [weak self] _ in
            self?.scheduleSnapshotRefresh(for: viewModel)
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
    let topUploaderStripRevision: Int
    let isTopUploaderStripLoading: Bool
    let itemCount: Int
    let firstItemID: String?
    let lastItemID: String?
    let itemsRevision: Int

    init(_ viewModel: DynamicViewModel) {
        state = viewModel.state
        hasMoreItems = viewModel.hasMoreItems
        topUploaderStripRevision = viewModel.topUploaderStripRevision
        isTopUploaderStripLoading = viewModel.isTopUploaderStripLoading
        itemCount = viewModel.items.count
        firstItemID = viewModel.items.first?.id
        lastItemID = viewModel.items.last?.id
        itemsRevision = viewModel.itemsRevision
    }
}
