import Foundation

@MainActor
final class DynamicFeedLifecycleCoordinator {
    private let api: BiliAPIClient
    private let sessionStore: SessionStore
    private let libraryStore: LibraryStore
    private let contentFilter: DynamicFeedContentFilter
    private let resourcePrefetchCoordinator: DynamicFeedResourcePrefetchCoordinator
    private let feedKind: DynamicFeedKind
    private let hostMID: Int?
    private let enhancesCategories: Bool
    private let accountIdentity: String
    private var requestGeneration = 0
    private var rawItems: [DynamicFeedItem] = []
    private var offset = ""
    private var hasMore = true
    private var seenCursors = Set<String>()
    private var topUploaderStripTask: Task<Void, Never>?

    var isLoggedIn: Bool {
        sessionStore.isLoggedIn
    }

    var hasMoreItems: Bool {
        hasMore
    }

    init(
        api: BiliAPIClient,
        sessionStore: SessionStore,
        libraryStore: LibraryStore,
        contentFilter: DynamicFeedContentFilter,
        resourcePrefetchCoordinator: DynamicFeedResourcePrefetchCoordinator,
        feedKind: DynamicFeedKind = .all,
        hostMID: Int? = nil
    ) {
        self.api = api
        self.sessionStore = sessionStore
        self.libraryStore = libraryStore
        self.contentFilter = contentFilter
        self.resourcePrefetchCoordinator = resourcePrefetchCoordinator
        self.feedKind = feedKind
        self.hostMID = hostMID
        enhancesCategories = libraryStore.dynamicFeedCategoriesExperimentEnabled
        accountIdentity = sessionStore.accountCacheIdentityKey(for: .dynamicFeed, multiAccountEnabled: libraryStore.multiAccountEnabled)
    }

    deinit {
        topUploaderStripTask?.cancel()
    }

    func prepareLoggedOutState() {
        requestGeneration &+= 1
        topUploaderStripTask?.cancel()
        topUploaderStripTask = nil
        rawItems = []
        seenCursors = []
        offset = ""
        hasMore = false
    }

    func loadInitialPage() async throws -> [DynamicFeedItem] {
        resetPagination()
        let generation = requestGeneration
        let page: DynamicFeedData
        if feedKind == .all {
            page = try await DynamicFeedWarmCache.shared.page(api: api, identityKey: cacheIdentityKey)
        } else {
            page = try await api.fetchDynamicFeed(kind: feedKind, hostMID: hostMID)
        }
        try validate(generation)
        return try await applyBatch(first: page, appending: false, generation: generation)
    }

    func cachedInitialPage() async -> [DynamicFeedItem]? {
        guard feedKind == .all else { return nil }
        resetPagination()
        let generation = requestGeneration
        guard let page = await DynamicFeedWarmCache.shared.cachedPage(identityKey: cacheIdentityKey) else {
            return nil
        }
        guard (try? validate(generation)) != nil else { return nil }
        return apply(page: page, prefetchDelay: 0)
    }

    func refreshPage() async throws -> [DynamicFeedItem] {
        requestGeneration &+= 1
        let generation = requestGeneration
        let identityKey = cacheIdentityKey
        let page = try await api.fetchDynamicFeed(kind: feedKind, hostMID: hostMID)
        try validate(generation)
        if feedKind == .all {
            await DynamicFeedWarmCache.shared.store(page, identityKey: identityKey)
        }
        return try await applyBatch(first: page, appending: false, generation: generation)
    }

    func loadMorePage() async throws -> [DynamicFeedItem] {
        let generation = requestGeneration
        let page = try await api.fetchDynamicFeed(offset: offset, kind: feedKind, hostMID: hostMID)
        try validate(generation)
        return try await applyBatch(first: page, appending: true, generation: generation)
    }

    func filteredCurrentItems() -> [DynamicFeedItem] {
        contentFilter.filtered(rawItems.filter { feedKind.includes($0) })
    }

    func refreshTopUploaderStripItems(setItems: @escaping ([DynamicTopUploaderStripItem]) -> Void) {
        topUploaderStripTask?.cancel()
        topUploaderStripTask = Task { [api] in
            let portal = try? await api.fetchDynamicPortal()
            guard !Task.isCancelled else { return }

            let items = Self.makeTopUploaderStripItems(
                portal: portal,
                limit: 10
            )
            await MainActor.run {
                setItems(items)
            }
        }
    }

    private func resetPagination() {
        requestGeneration &+= 1
        offset = ""
        hasMore = true
        seenCursors = []
    }

    private var cacheIdentityKey: String {
        sessionStore.accountCacheIdentityKey(
            for: .dynamicFeed,
            multiAccountEnabled: libraryStore.multiAccountEnabled
        )
    }

    private func validate(_ generation: Int) throws {
        try Task.checkCancellation()
        guard generation == requestGeneration, cacheIdentityKey == accountIdentity else {
            throw CancellationError()
        }
    }

    private func applyBatch(first: DynamicFeedData, appending: Bool, generation: Int) async throws -> [DynamicFeedItem] {
        if !enhancesCategories {
            if !appending { return apply(page: first, prefetchDelay: 0.08) }
            let more = contentFilter.displayable(first.items)
            rawItems = contentFilter.uniqueAppendItems(more, to: rawItems)
            offset = first.offset ?? offset
            hasMore = first.hasMore ?? false
            resourcePrefetchCoordinator.scheduleResourcePrefetch(for: more.filter { feedKind.includes($0) }, initialDelay: 0.75)
            return filteredCurrentItems()
        }

        // Commit a batch atomically: a failed continuation leaves the previous
        // cursor and list intact so retry cannot skip unseen content.
        let base = appending ? rawItems : []
        let baseIDs = Set(base.map(\.id))
        var accumulated = base
        var cursor = appending ? offset : ""
        var visited = appending ? seenCursors : Set<String>()
        if !cursor.isEmpty { visited.insert(cursor) }
        var page = first
        var more = false
        for attempt in 0..<3 {
            try validate(generation)
            let items = contentFilter.displayable(page.items)
            accumulated = contentFilter.uniqueAppendItems(items, to: accumulated)
            let next = page.offset ?? ""
            more = page.hasMore == true && !next.isEmpty && visited.insert(next).inserted
            cursor = next
            let visibleNew = contentFilter.filtered(accumulated.filter { !baseIDs.contains($0.id) && feedKind.includes($0) })
            guard visibleNew.isEmpty, more, attempt < 2 else { break }
            page = try await api.fetchDynamicFeed(offset: cursor, kind: feedKind, hostMID: hostMID)
        }
        try validate(generation)
        rawItems = accumulated
        offset = cursor
        hasMore = more
        seenCursors = visited
        let visible = filteredCurrentItems()
        let newVisible = visible.filter { !baseIDs.contains($0.id) }
        resourcePrefetchCoordinator.scheduleResourcePrefetch(for: newVisible, initialDelay: appending ? 0.75 : 0.08)
        if !visible.isEmpty { StageOneBaselineMetricsStore.shared.markDynamicFirstData() }
        return visible
    }

    private func apply(page: DynamicFeedData, prefetchDelay: TimeInterval) -> [DynamicFeedItem] {
        let displayable = contentFilter.displayable(page.items)
        rawItems = enhancesCategories ? contentFilter.uniqueAppendItems(displayable, to: []) : displayable
        let filteredItems = filteredCurrentItems()
        if !filteredItems.isEmpty {
            StageOneBaselineMetricsStore.shared.markDynamicFirstData()
        }
        resourcePrefetchCoordinator.scheduleResourcePrefetch(for: filteredItems, initialDelay: prefetchDelay)
        offset = page.offset ?? ""
        hasMore = page.hasMore ?? false
        if enhancesCategories {
            hasMore = hasMore && !offset.isEmpty
            seenCursors = offset.isEmpty ? [] : [offset]
        }
        return filteredItems
    }

    private nonisolated static func makeTopUploaderStripItems(
        portal: DynamicPortalData?,
        limit: Int
    ) -> [DynamicTopUploaderStripItem] {
        var items: [DynamicTopUploaderStripItem] = []
        var usedMIDs = Set<Int>()

        for liveUser in portal?.liveUsers?.items ?? [] {
            let owner = liveUser.owner
            guard owner.mid <= 0 || usedMIDs.insert(owner.mid).inserted else { continue }
            items.append(DynamicTopUploaderStripItem(owner: owner, liveRoom: liveUser.liveRoom))
            guard items.count < limit else { return items }
        }

        for upItem in portal?.upList?.items ?? [] {
            let owner = upItem.owner
            guard owner.mid > 0, usedMIDs.insert(owner.mid).inserted else { continue }
            items.append(DynamicTopUploaderStripItem(owner: owner, liveRoom: nil))
            guard items.count < limit else { break }
        }

        return items
    }
}
