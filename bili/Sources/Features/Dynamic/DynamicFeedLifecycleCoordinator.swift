import Foundation

@MainActor
final class DynamicFeedLifecycleCoordinator {
    private let api: BiliAPIClient
    private let sessionStore: SessionStore
    private let contentFilter: DynamicFeedContentFilter
    private let resourcePrefetchCoordinator: DynamicFeedResourcePrefetchCoordinator
    private var rawItems: [DynamicFeedItem] = []
    private var offset = ""
    private var hasMore = true
    private var followedLiveTask: Task<Void, Never>?

    var isLoggedIn: Bool {
        sessionStore.isLoggedIn
    }

    var hasMoreItems: Bool {
        hasMore
    }

    init(
        api: BiliAPIClient,
        sessionStore: SessionStore,
        contentFilter: DynamicFeedContentFilter,
        resourcePrefetchCoordinator: DynamicFeedResourcePrefetchCoordinator
    ) {
        self.api = api
        self.sessionStore = sessionStore
        self.contentFilter = contentFilter
        self.resourcePrefetchCoordinator = resourcePrefetchCoordinator
    }

    deinit {
        followedLiveTask?.cancel()
    }

    func prepareLoggedOutState() {
        followedLiveTask?.cancel()
        followedLiveTask = nil
        rawItems = []
        offset = ""
        hasMore = false
    }

    func loadInitialPage() async throws -> [DynamicFeedItem] {
        resetPagination()
        let page = try await DynamicFeedWarmCache.shared.page(api: api)
        return apply(page: page, prefetchDelay: 0.08)
    }

    func refreshPage() async throws -> [DynamicFeedItem] {
        resetPagination()
        let page = try await api.fetchDynamicFeed()
        await DynamicFeedWarmCache.shared.store(page)
        return apply(page: page, prefetchDelay: 0.08)
    }

    func loadMorePage() async throws -> [DynamicFeedItem] {
        let page = try await api.fetchDynamicFeed(offset: offset)
        let moreItems = contentFilter.displayable(page.items)
        rawItems = contentFilter.uniqueAppendItems(moreItems, to: rawItems)
        let filteredItems = filteredCurrentItems()
        resourcePrefetchCoordinator.scheduleResourcePrefetch(for: moreItems, initialDelay: 0.75)
        offset = page.offset ?? offset
        hasMore = page.hasMore ?? false
        return filteredItems
    }

    func filteredCurrentItems() -> [DynamicFeedItem] {
        contentFilter.filtered(rawItems)
    }

    func refreshFollowedLiveRooms(setRooms: @escaping ([LiveRoom]) -> Void) {
        followedLiveTask?.cancel()
        followedLiveTask = Task { [api] in
            do {
                let rooms = try await api.fetchFollowedLiveRooms(page: 1, pageSize: 20)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    setRooms(Array(rooms.prefix(12)))
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    setRooms([])
                }
            }
        }
    }

    private func resetPagination() {
        offset = ""
        hasMore = true
    }

    private func apply(page: DynamicFeedData, prefetchDelay: TimeInterval) -> [DynamicFeedItem] {
        rawItems = contentFilter.displayable(page.items)
        let filteredItems = filteredCurrentItems()
        resourcePrefetchCoordinator.scheduleResourcePrefetch(for: filteredItems, initialDelay: prefetchDelay)
        offset = page.offset ?? ""
        hasMore = page.hasMore ?? false
        return filteredItems
    }
}
