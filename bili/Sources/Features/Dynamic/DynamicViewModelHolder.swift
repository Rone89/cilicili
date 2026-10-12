import Combine

@MainActor
final class DynamicViewModelHolder: ObservableObject {
    @Published var viewModel: DynamicViewModel?
    private var cancellable: AnyCancellable?
    private var snapshotRefreshTask: Task<Void, Never>?
    private var lastSnapshot: DynamicRenderSnapshot?
    private var viewModels: [DynamicFeedQuery: DynamicViewModel] = [:]
    private var recentUPQueries: [DynamicFeedQuery] = []

    var topUploaderStripViewModel: DynamicViewModel? {
        viewModels[DynamicFeedQuery(kind: .all)]
    }

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
        recentUPQueries = []
        installViewModel(api: api, libraryStore: libraryStore, sessionStore: sessionStore)
    }

    func selectFeed(_ kind: DynamicFeedKind, hostMID: Int? = nil, api: BiliAPIClient, libraryStore: LibraryStore, sessionStore: SessionStore) {
        let query = DynamicFeedQuery(kind: kind, hostMID: hostMID)
        guard kind != .up || (hostMID ?? 0) > 0 else { return }
        guard viewModel?.query != query else { return }
        snapshotRefreshTask?.cancel()
        snapshotRefreshTask = nil
        cancellable = nil
        let model = viewModels[query] ?? DynamicViewModel(
            api: api, libraryStore: libraryStore, sessionStore: sessionStore, feedKind: kind, hostMID: hostMID
        )
        observe(model)
        if kind == .up {
            recentUPQueries.removeAll { $0 == query }
            recentUPQueries.append(query)
            if recentUPQueries.count > 3 {
                let evicted = recentUPQueries.removeFirst()
                viewModels.removeValue(forKey: evicted)?.invalidateAccount()
            }
        }
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
        viewModels[viewModel.query] = viewModel
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
