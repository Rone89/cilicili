import Foundation
import Combine

enum UploaderVideoOrder: String, CaseIterable, Identifiable, Sendable {
    case pubdate
    case click

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pubdate:
            return "最新发布"
        case .click:
            return "最多播放"
        }
    }
}

@MainActor
final class UploaderViewModel: ObservableObject {
    @Published var profile: UploaderProfile?
    @Published var videos: [VideoItem] = []
    @Published var state: LoadingState = .idle
    @Published private(set) var profileState: LoadingState = .idle
    @Published private(set) var isFollowing = false
    @Published private(set) var followerCount: Int?
    @Published private(set) var followingCount: Int?
    @Published private(set) var likeCount: Int?
    @Published private(set) var archiveCount: Int?
    @Published private(set) var isMutatingFollow = false
    @Published var followMessage: String?
    @Published private(set) var videoOrder: UploaderVideoOrder = .pubdate
    @Published private(set) var hasMoreVideos = true
    @Published var dynamicItems: [DynamicFeedItem] = []
    @Published var dynamicState: LoadingState = .idle
    let seedOwner: VideoOwner
    let viewerIdentity: UploaderSpaceRequestIdentity
    @Published private(set) var spaceOverview: UploaderSpaceOverview?
    @Published private(set) var spaceOverviewState: LoadingState = .idle
    @Published private(set) var ownSpaceFavorites: UploaderSpaceFavoriteGroup?
    @Published private(set) var ownSpaceFavoritesState: LoadingState = .idle
    @Published private(set) var ownSpaceBangumi: UploaderSpaceVideoGroup?
    @Published private(set) var ownSpaceBangumiState: LoadingState = .idle
    @Published private(set) var viewerRelationState: LoadingState = .idle
    @Published private(set) var ownBangumiItems: [UploaderSpaceVideoPreview] = []
    @Published private(set) var ownBangumiListState: LoadingState = .idle
    @Published private(set) var ownBangumiLoadMoreState: LoadingState = .idle
    @Published private(set) var ownBangumiHasMore = false
    @Published private(set) var favoriteFolderPreviews: [Int: [AccountVideoEntry]] = [:]
    @Published private(set) var favoriteFolderPreviewStates: [Int: LoadingState] = [:]
    private var ownBangumiPage = 0

    var spaceSections: [UploaderSpaceSection] {
        isOwnSpace ? UploaderSpaceSection.allCases : [.home, .dynamics, .videos]
    }

    var favoritePreview: UploaderSpaceFavoriteGroup? {
        if let group = spaceOverview?.favorites, group.items.contains(where: { $0.folder.id > 0 }) { return group }
        return ownSpaceFavorites ?? spaceOverview?.favorites
    }

    var bangumiPreview: UploaderSpaceVideoGroup? {
        if let group = spaceOverview?.bangumi, group.items.contains(where: { $0.seasonID != nil }) { return group }
        return ownSpaceBangumi ?? spaceOverview?.bangumi
    }

    private let api: BiliAPIClient
    private let viewerSnapshot: BiliAPIClient.RequestSnapshot
    private let uploaderVideosTimeoutNanoseconds: UInt64 = 8_000_000_000
    private var isLoadingSpaceOverview = false
    private var page = 1
    private var videoCursor: UploaderVideoPageCursor?
    private var dynamicOffset: String?
    private var dynamicHasMore = true

    init(seedOwner: VideoOwner, api: BiliAPIClient) {
        self.seedOwner = seedOwner
        self.api = api
        viewerSnapshot = api.requestSnapshot()
        viewerIdentity = UploaderSpaceRequestIdentity(viewerSnapshot)
    }

    var isCurrentViewerContext: Bool {
        viewerIdentity == UploaderSpaceRequestIdentity(api.requestSnapshot())
    }

    private var canApplyResponse: Bool {
        isCurrentViewerContext && !Task.isCancelled
    }

    var canChangeRelation: Bool {
        isCurrentViewerContext && viewerIdentity.isLoggedIn && viewerIdentity.isPurposeEnabled
            && !viewerIdentity.guestModeEnabled && !isOwnSpace
    }

    var isOwnSpace: Bool { viewerIdentity.ownsSpace(mid: seedOwner.mid) }

    func loadSpaceOverview(force: Bool = false) async {
        guard isCurrentViewerContext, !isLoadingSpaceOverview else { return }
        guard force || spaceOverviewState == .idle else { return }
        isLoadingSpaceOverview = true
        spaceOverviewState = .loading
        profileState = .loading
        defer {
            isLoadingSpaceOverview = false
            if Task.isCancelled && isCurrentViewerContext {
                spaceOverviewState = .idle
                profileState = profile == nil ? .idle : .loaded
            }
        }
        do {
            let overview = try await api.fetchUploaderSpaceOverview(mid: seedOwner.mid, snapshot: viewerSnapshot)
            guard isCurrentViewerContext, !Task.isCancelled else { return }
            spaceOverview = overview
            applyProfile(overview.profile, preservesUnknownFollowing: false)
            spaceOverviewState = .loaded
            profileState = .loaded
        } catch {
            guard isCurrentViewerContext, !Task.isCancelled else { return }
            let overviewError = error.localizedDescription
            // Keep the existing content tabs usable when the APP aggregation route fails.
            do {
                let fallback = try await api.fetchUploaderSpaceProfileFallback(mid: seedOwner.mid, snapshot: viewerSnapshot)
                guard isCurrentViewerContext, !Task.isCancelled else { return }
                applyProfile(fallback)
                profileState = .loaded
            } catch {
                guard isCurrentViewerContext, !Task.isCancelled else { return }
                profileState = .failed(error.localizedDescription)
            }
            if isCurrentViewerContext, !Task.isCancelled {
                spaceOverviewState = .failed(overviewError)
            }
        }
        guard isCurrentViewerContext, !Task.isCancelled else { return }
        if spaceOverviewState == .loaded, spaceOverview?.profile.following == nil {
            await loadViewerRelation(force: force)
        }
        // Sequential, bounded preview requests only when the APP aggregation omitted usable data.
        await loadOwnSpaceFavorites(force: force)
        await loadOwnSpaceBangumi(force: force)
    }

    func loadOwnSpaceFavorites(force: Bool = false, requiresCompleteList: Bool = false) async {
        guard isOwnSpace, isCurrentViewerContext, !Task.isCancelled,
              !ownSpaceFavoritesState.isLoading else { return }
        guard requiresCompleteList || spaceOverview?.favorites?.items.contains(where: { $0.folder.id > 0 }) != true else { return }
        guard force || ownSpaceFavoritesState == .idle else { return }
        ownSpaceFavoritesState = .loading
        defer {
            if Task.isCancelled, isCurrentViewerContext { ownSpaceFavoritesState = .idle }
        }
        do {
            let group = try await api.fetchOwnSpaceFavoritePreview(mid: seedOwner.mid, snapshot: viewerSnapshot)
            guard canApplyResponse else { return }
            ownSpaceFavorites = group
            ownSpaceFavoritesState = .loaded
        } catch {
            guard canApplyResponse else { return }
            ownSpaceFavoritesState = .failed(error.localizedDescription)
        }
    }

    func loadViewerRelation(force: Bool = false) async {
        guard canChangeRelation, !Task.isCancelled,
              !viewerRelationState.isLoading, force || viewerRelationState == .idle else { return }
        viewerRelationState = .loading
        defer { if Task.isCancelled { viewerRelationState = .idle } }
        do {
            let relation = try await api.fetchSpaceViewerRelation(mid: seedOwner.mid, snapshot: viewerSnapshot)
            guard canApplyResponse else { return }
            applyProfile(relation.profilePatch)
            viewerRelationState = .loaded
        } catch {
            guard canApplyResponse else { return }
            viewerRelationState = .failed(error.localizedDescription)
        }
    }

    // Each visible section loads a bounded three-item preview per folder, sequentially.
    // Cache belongs to this captured viewer context and is discarded with the space model.
    func loadFavoriteFolderPreviews(folderIDs: [Int], force: Bool = false) async {
        var seen = Set<Int>()
        for folderID in folderIDs where folderID > 0 && seen.insert(folderID).inserted {
            guard canApplyResponse else { return }
            let state = favoriteFolderPreviewStates[folderID] ?? .idle
            guard !state.isLoading, force || state == .idle else { continue }
            favoriteFolderPreviewStates[folderID] = .loading
            do {
                let result = try await api.fetchFavoriteFolderVideoPage(folderID: folderID, pageSize: 3, viewerSnapshot: viewerSnapshot)
                guard canApplyResponse else {
                    if Task.isCancelled { favoriteFolderPreviewStates[folderID] = .idle }
                    return
                }
                var entryIDs = Set<String>()
                favoriteFolderPreviews[folderID] = Array(result.entries.filter { entryIDs.insert($0.id).inserted }.prefix(3))
                favoriteFolderPreviewStates[folderID] = .loaded
            } catch {
                guard canApplyResponse else {
                    if Task.isCancelled { favoriteFolderPreviewStates[folderID] = .idle }
                    return
                }
                // A failed refresh keeps the previously displayed preview.
                favoriteFolderPreviewStates[folderID] = .failed(error.localizedDescription)
            }
        }
    }

    func loadOwnSpaceBangumi(force: Bool = false) async {
        guard isOwnSpace, isCurrentViewerContext, !Task.isCancelled,
              !ownSpaceBangumiState.isLoading else { return }
        guard spaceOverview?.bangumi?.items.contains(where: { $0.seasonID != nil }) != true else { return }
        guard force || ownSpaceBangumiState == .idle else { return }
        ownSpaceBangumiState = .loading
        defer {
            if Task.isCancelled, isCurrentViewerContext { ownSpaceBangumiState = .idle }
        }
        do {
            let group = try await api.fetchOwnSpaceBangumiPreview(mid: seedOwner.mid, snapshot: viewerSnapshot)
            guard canApplyResponse else { return }
            ownSpaceBangumi = group
            ownSpaceBangumiState = .loaded
        } catch {
            guard canApplyResponse else { return }
            ownSpaceBangumiState = .failed(error.localizedDescription)
        }
    }

    func loadVideosIfNeeded() async {
        guard isCurrentViewerContext, state != .loaded, !state.isLoading else { return }
        await refresh()
    }

    func loadOwnBangumiList(force: Bool = false) async {
        guard isOwnSpace, canApplyResponse,
              !ownBangumiListState.isLoading, !ownBangumiLoadMoreState.isLoading,
              force || ownBangumiListState == .idle else { return }
        ownBangumiListState = .loading
        defer { if Task.isCancelled { ownBangumiListState = .idle } }
        do {
            let result = try await api.fetchOwnSpaceBangumiPage(mid: seedOwner.mid, snapshot: viewerSnapshot, page: 1)
            guard canApplyResponse else { return }
            var seen = Set<Int>()
            ownBangumiItems = result.list.filter { item in
                item.seasonID.map { seen.insert($0).inserted } == true
            }
            ownBangumiPage = 1
            ownBangumiHasMore = !ownBangumiItems.isEmpty && (result.total.map { ownBangumiItems.count < $0 } ?? (result.list.count == 20))
            ownBangumiLoadMoreState = .idle
            ownBangumiListState = .loaded
        } catch {
            guard canApplyResponse else { return }
            ownBangumiListState = .failed(error.localizedDescription)
        }
    }

    func loadMoreOwnBangumiIfNeeded(seasonID: Int?) async {
        guard seasonID != nil, seasonID == ownBangumiItems.last?.seasonID,
              ownBangumiLoadMoreState == .idle else { return }
        await loadMoreOwnBangumi()
    }

    func loadMoreOwnBangumi() async {
        guard isOwnSpace, canApplyResponse, ownBangumiHasMore,
              !ownBangumiListState.isLoading, !ownBangumiLoadMoreState.isLoading else { return }
        ownBangumiLoadMoreState = .loading
        defer { if Task.isCancelled { ownBangumiLoadMoreState = .idle } }
        do {
            let result = try await api.fetchOwnSpaceBangumiPage(mid: seedOwner.mid, snapshot: viewerSnapshot, page: ownBangumiPage + 1)
            guard canApplyResponse else { return }
            var seen = Set(ownBangumiItems.compactMap(\.seasonID))
            let incoming = result.list.filter { item in
                item.seasonID.map { seen.insert($0).inserted } == true
            }
            ownBangumiItems.append(contentsOf: incoming)
            ownBangumiPage += 1
            ownBangumiHasMore = !incoming.isEmpty && (result.total.map { ownBangumiItems.count < $0 } ?? (result.list.count == 20))
            ownBangumiLoadMoreState = .idle
        } catch {
            guard canApplyResponse else { return }
            ownBangumiLoadMoreState = .failed(error.localizedDescription)
        }
    }

    func loadInitial() async {
        await loadSpaceOverview()
    }

    func refresh() async {
        guard isCurrentViewerContext, !state.isLoading else { return }
        state = .loading
        defer {
            if Task.isCancelled, isCurrentViewerContext {
                state = .idle
            }
        }
        page = 1
        videoCursor = nil
        hasMoreVideos = true
        do {
            let result = try await fetchUploaderVideosWithTimeout(page: page)
            guard canApplyResponse else { return }
            applyVideoPage(result, appending: false)
            state = .loaded
        } catch {
            guard canApplyResponse else { return }
            state = .failed(error.localizedDescription)
        }
    }

    func loadMoreIfNeeded(current video: VideoItem?) async {
        guard isCurrentViewerContext, let video,
              videos.last?.id == video.id,
              hasMoreVideos,
              !state.isLoading
        else { return }
        state = .loading
        var didApplyResponse = false
        defer {
            if Task.isCancelled, isCurrentViewerContext, !didApplyResponse {
                page = max(1, page - 1)
                state = .idle
            }
        }
        page += 1
        do {
            let result = try await fetchUploaderVideosWithTimeout(page: page)
            guard canApplyResponse else { return }
            applyVideoPage(result, appending: true)
            didApplyResponse = true
            state = .loaded
        } catch {
            guard canApplyResponse else { return }
            page = max(1, page - 1)
            state = .failed(error.localizedDescription)
        }
    }

    func changeVideoOrder(_ order: UploaderVideoOrder) async {
        guard isCurrentViewerContext, order != videoOrder, !state.isLoading else { return }
        videoOrder = order
        videos = []
        await refresh()
    }

    var hasMoreDynamicItems: Bool {
        dynamicHasMore
    }

    func loadDynamicsIfNeeded() async {
        if dynamicState == .loaded { return }
        guard dynamicItems.isEmpty, !dynamicState.isLoading else { return }
        await refreshDynamics()
    }

    func refreshDynamics() async {
        guard isCurrentViewerContext, !dynamicState.isLoading else { return }
        dynamicState = .loading
        defer {
            if Task.isCancelled, isCurrentViewerContext {
                dynamicState = .idle
            }
        }
        dynamicOffset = nil
        dynamicHasMore = true
        do {
            let page = try await api.fetchUploaderDynamicFeed(mid: seedOwner.mid)
            guard canApplyResponse else { return }
            applyDynamicPage(page, appending: false)
            dynamicState = .loaded
        } catch {
            guard canApplyResponse else { return }
            dynamicState = .failed(error.localizedDescription)
        }
    }

    func loadMoreDynamicsIfNeeded(current item: DynamicFeedItem?) async {
        guard let item, dynamicItems.last?.id == item.id else { return }
        await loadMoreDynamics()
    }

    func loadMoreDynamics() async {
        guard isCurrentViewerContext, dynamicHasMore, !dynamicState.isLoading else { return }
        dynamicState = .loading
        defer {
            if Task.isCancelled, isCurrentViewerContext {
                dynamicState = .idle
            }
        }
        do {
            let page = try await api.fetchUploaderDynamicFeed(mid: seedOwner.mid, offset: dynamicOffset)
            guard canApplyResponse else { return }
            applyDynamicPage(page, appending: true)
            dynamicState = .loaded
        } catch {
            guard canApplyResponse else { return }
            dynamicState = .failed(error.localizedDescription)
        }
    }

    private func fetchUploaderVideosWithTimeout(page: Int) async throws -> UploaderVideoPageResult {
        try await withThrowingTaskGroup(of: UploaderVideoPageResult.self) { group in
            let mid = seedOwner.mid
            let timeout = uploaderVideosTimeoutNanoseconds
            let cursor = videoCursor
            let order = videoOrder

            group.addTask(priority: .userInitiated) {
                try await self.api.fetchUploaderVideoPage(mid: mid, page: page, cursor: cursor, order: order)
            }
            group.addTask(priority: .utility) {
                try await Task.sleep(nanoseconds: timeout)
                throw BiliAPIError.api(code: -1, message: "投稿加载超时，请稍后重试")
            }

            guard let pageResult = try await group.next() else {
                group.cancelAll()
                throw BiliAPIError.emptyData
            }
            group.cancelAll()
            return pageResult
        }
    }

    @discardableResult
    func toggleFollow() async -> Bool {
        guard isCurrentViewerContext, canChangeRelation else { return false }
        guard !isMutatingFollow else { return false }
        guard seedOwner.mid > 0 else {
            followMessage = "没有找到 UP 主 UID，无法关注"
            return false
        }

        let targetState = !isFollowing
        let previousState = isFollowing
        let previousFollowerCount = followerCount
        isMutatingFollow = true
        isFollowing = targetState
        if let followerCount {
            self.followerCount = max(0, followerCount + (targetState ? 1 : -1))
        }
        followMessage = targetState ? "正在关注" : "正在取消关注"

        do {
            try await api.setUploaderFollowing(
                mid: seedOwner.mid, following: targetState,
                expectedAccountMID: viewerIdentity.accountMID
            )
            guard isCurrentViewerContext else { return false }
            followMessage = targetState ? "已关注" : "已取消关注"
            isMutatingFollow = false
            Task { await loadSpaceOverview(force: true) }
            return true
        } catch {
            guard isCurrentViewerContext else { return false }
            isFollowing = previousState
            followerCount = previousFollowerCount
            followMessage = followFailureMessage(error)
            isMutatingFollow = false
            return false
        }
    }

    @discardableResult
    private func appendUnique(_ more: [VideoItem]) -> Int {
        let existing = Set(videos.map(\.id))
        let unique = more.filter { !existing.contains($0.id) }
        videos.append(contentsOf: unique)
        return unique.count
    }

    private func applyVideoPage(_ page: UploaderVideoPageResult, appending: Bool) {
        videoCursor = page.nextCursor
        if let totalCount = page.totalCount {
            archiveCount = totalCount
        }
        if appending {
            let appendedCount = appendUnique(page.videos)
            hasMoreVideos = page.hasMore && appendedCount > 0
        } else {
            videos = page.videos
            hasMoreVideos = page.hasMore && !page.videos.isEmpty
        }
    }

    private func applyDynamicPage(_ page: DynamicFeedData, appending: Bool) {
        dynamicOffset = page.offset
        dynamicHasMore = page.hasMore ?? false
        let incoming = page.items ?? []
        if appending {
            let existing = Set(dynamicItems.map(\.id))
            dynamicItems.append(contentsOf: incoming.filter { !existing.contains($0.id) })
        } else {
            dynamicItems = incoming
        }
    }

    private func applyProfile(_ profile: UploaderProfile, preservesUnknownFollowing: Bool = true) {
        var mergedProfile = self.profile?.merged(with: profile) ?? profile
        if !preservesUnknownFollowing, profile.following == nil {
            mergedProfile = UploaderProfile(card: mergedProfile.card, follower: mergedProfile.follower,
                                            following: nil, likeNum: mergedProfile.likeNum,
                                            archiveCount: mergedProfile.archiveCount)
            isFollowing = false
        }
        self.profile = mergedProfile
        if let isFollowing = profile.following {
            self.isFollowing = isFollowing
        }
        followerCount = mergedProfile.visibleFollowerCount ?? followerCount
        followingCount = mergedProfile.visibleFollowingCount ?? followingCount
        likeCount = mergedProfile.visibleLikeCount ?? likeCount
        archiveCount = mergedProfile.visibleArchiveCount ?? archiveCount
        followMessage = nil
    }

    private func followFailureMessage(_ error: Error) -> String {
        if case BiliAPIError.missingSESSDATA = error {
            return "登录后才能关注 UP 主"
        }
        return "关注状态更新失败：\(error.localizedDescription)"
    }
}
