import Combine
import Foundation

@MainActor
final class DynamicViewModel: ObservableObject {
    @Published var items: [DynamicFeedItem] = [] {
        didSet {
            itemsRevision &+= 1
        }
    }
    @Published private(set) var topUploaderStripItems: [DynamicTopUploaderStripItem] = [] {
        didSet {
            topUploaderStripRevision &+= 1
        }
    }
    @Published private(set) var isTopUploaderStripLoading = false
    @Published private(set) var isRefreshing = false
    @Published var state: LoadingState = .idle
    @Published private(set) var itemsRevision = 0
    @Published private(set) var topUploaderStripRevision = 0

    private let lifecycleCoordinator: DynamicFeedLifecycleCoordinator
    private var filterCancellable: AnyCancellable?
    private var loadRequestRevision = 0
    private var cachedInitialRefreshTask: Task<Void, Never>?

    var hasMoreItems: Bool {
        lifecycleCoordinator.hasMoreItems
    }

    init(api: BiliAPIClient, libraryStore: LibraryStore, sessionStore: SessionStore) {
        let contentFilter = DynamicFeedContentFilter(libraryStore: libraryStore)
        let resourcePrefetchCoordinator = DynamicFeedResourcePrefetchCoordinator(
            api: api,
            libraryStore: libraryStore
        )
        lifecycleCoordinator = DynamicFeedLifecycleCoordinator(
            api: api,
            sessionStore: sessionStore,
            libraryStore: libraryStore,
            contentFilter: contentFilter,
            resourcePrefetchCoordinator: resourcePrefetchCoordinator
        )
        filterCancellable = libraryStore.$blocksAdDynamics
            .combineLatest(libraryStore.$blocksGoodsDynamics)
            .combineLatest(libraryStore.$blockedDynamicKeywords)
            .removeDuplicates { lhs, rhs in
                lhs.0.0 == rhs.0.0
                    && lhs.0.1 == rhs.0.1
                    && lhs.1 == rhs.1
            }
            .dropFirst()
            .sink { [weak self] _ in
                self?.applyCurrentFilter()
            }
    }

    deinit {
        cachedInitialRefreshTask?.cancel()
    }

    func loadInitial() async {
        guard items.isEmpty else { return }
        guard lifecycleCoordinator.isLoggedIn else {
            prepareLoggedOutState()
            return
        }
        loadRequestRevision &+= 1
        let requestRevision = loadRequestRevision
        if let cachedItems = await lifecycleCoordinator.cachedInitialPage() {
            guard requestRevision == loadRequestRevision else { return }
            items = cachedItems
            state = .loaded
            refreshTopUploaderStrip()
            refreshCachedInitialPage(requestRevision: requestRevision)
            return
        }
        state = .loading
        refreshTopUploaderStrip()
        do {
            items = try await lifecycleCoordinator.loadInitialPage()
            state = .loaded
        } catch is CancellationError {
            guard requestRevision == loadRequestRevision else { return }
            state = .idle
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func refresh() async {
        guard lifecycleCoordinator.isLoggedIn, !isRefreshing else {
            if !lifecycleCoordinator.isLoggedIn {
                prepareLoggedOutState()
            }
            return
        }
        loadRequestRevision &+= 1
        cachedInitialRefreshTask?.cancel()
        cachedInitialRefreshTask = nil
        isRefreshing = true
        defer {
            isRefreshing = false
        }
        state = .loading
        refreshTopUploaderStrip()
        do {
            items = try await lifecycleCoordinator.refreshPage()
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func loadMoreIfNeeded(current item: DynamicFeedItem?) async {
        guard let item, items.last?.id == item.id else { return }
        await loadMore()
    }

    func loadMore() async {
        guard lifecycleCoordinator.isLoggedIn else {
            prepareLoggedOutState()
            return
        }
        guard lifecycleCoordinator.hasMoreItems,
              !state.isLoading,
              cachedInitialRefreshTask == nil
        else { return }
        state = .loading
        do {
            items = try await lifecycleCoordinator.loadMorePage()
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func prepareLoggedOutState() {
        loadRequestRevision &+= 1
        cachedInitialRefreshTask?.cancel()
        cachedInitialRefreshTask = nil
        lifecycleCoordinator.prepareLoggedOutState()
        items = []
        topUploaderStripItems = []
        isTopUploaderStripLoading = false
        state = .idle
    }

    private func refreshCachedInitialPage(requestRevision: Int) {
        cachedInitialRefreshTask?.cancel()
        cachedInitialRefreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let refreshedItems = try await lifecycleCoordinator.refreshPage()
                guard !Task.isCancelled, requestRevision == loadRequestRevision else { return }
                items = refreshedItems
                state = .loaded
            } catch is CancellationError {
                return
            } catch {
                // Keep the cached feed visible when the background refresh fails.
            }
            guard requestRevision == loadRequestRevision else { return }
            cachedInitialRefreshTask = nil
        }
    }

    private func applyCurrentFilter() {
        items = lifecycleCoordinator.filteredCurrentItems()
    }

    private func refreshTopUploaderStrip() {
        isTopUploaderStripLoading = true
        lifecycleCoordinator.refreshTopUploaderStripItems { [weak self] items in
            self?.topUploaderStripItems = items
            self?.isTopUploaderStripLoading = false
        }
    }
}
