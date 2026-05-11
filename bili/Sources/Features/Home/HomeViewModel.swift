import Foundation
import Combine

enum HomeFeedMode: String, CaseIterable, Hashable {
    case recommend
    case popular

    var title: String {
        switch self {
        case .recommend:
            return "推荐"
        case .popular:
            return "热门"
        }
    }
}

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var videos: [VideoItem] = []
    @Published var state: LoadingState = .idle
    @Published var mode: HomeFeedMode = .recommend
    @Published var isRefreshing = false
    @Published private(set) var feedContentVersion = 0

    private let api: BiliAPIClient
    private let libraryStore: LibraryStore
    private var freshIndex = 0
    private var popularPage = 1
    private var requestRevision = 0
    private var lastUserRefreshDate: Date?
    private var privacyCancellable: AnyCancellable?
    private var authorAvatarCache: [Int: String] = [:]
    private var authorAvatarRequestsInFlight = Set<Int>()

    init(api: BiliAPIClient, libraryStore: LibraryStore, initialMode: HomeFeedMode = .recommend) {
        self.api = api
        self.libraryStore = libraryStore
        mode = initialMode
        privacyCancellable = libraryStore.$guestModeEnabled
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.reloadForGuestModeChange() }
            }
    }

    func loadInitial() async {
        guard videos.isEmpty else { return }
        await refresh(resetCursor: true)
    }

    func switchMode(_ newMode: HomeFeedMode) async {
        guard mode != newMode else { return }
        mode = newMode
        videos = []
        await refresh(resetCursor: true)
    }

    func refreshFromUserPull() async {
        guard !isRefreshing else { return }
        let now = Date()
        if let lastUserRefreshDate,
           now.timeIntervalSince(lastUserRefreshDate) < 1.0 {
            return
        }
        lastUserRefreshDate = now
        await refresh()
    }

    func refresh(resetCursor shouldResetCursor: Bool = false) async {
        let previousIDs = videos.map(\.id)
        requestRevision += 1
        let revision = requestRevision
        state = .loading
        isRefreshing = true
        defer {
            if revision == requestRevision {
                isRefreshing = false
            }
        }
        if shouldResetCursor {
            resetCursor()
        } else {
            advanceRefreshCursor()
        }
        do {
            let refreshedVideos = try await fetchFreshPage(replacing: previousIDs)
            guard revision == requestRevision else { return }
            replaceVideos(refreshedVideos, previousIDs: previousIDs)
            state = .loaded
        } catch {
            guard revision == requestRevision else { return }
            state = .failed(error.localizedDescription)
        }
    }

    func reloadForGuestModeChange() async {
        guard mode == .recommend else { return }
        videos = []
        await refresh(resetCursor: true)
    }

    func loadMoreIfNeeded(current video: VideoItem?) async {
        guard let video,
              videos.last?.id == video.id,
              !state.isLoading,
              !isRefreshing
        else { return }
        let revision = requestRevision
        state = .loading
        advanceCursor()
        do {
            let moreVideos = try await fetchCurrentPage()
            guard revision == requestRevision else { return }
            appendUnique(moreVideos)
            state = .loaded
        } catch {
            guard revision == requestRevision else { return }
            rollbackCursor()
            state = .failed(error.localizedDescription)
        }
    }

    func loadAuthorAvatarIfNeeded(for video: VideoItem) async {
        guard let owner = video.owner, owner.mid > 0, owner.face?.isEmpty != false else { return }

        if let cachedFace = authorAvatarCache[owner.mid] {
            updateAuthorAvatar(mid: owner.mid, face: cachedFace)
            return
        }

        guard !authorAvatarRequestsInFlight.contains(owner.mid) else { return }
        authorAvatarRequestsInFlight.insert(owner.mid)
        defer { authorAvatarRequestsInFlight.remove(owner.mid) }

        guard let profile = try? await api.fetchUploaderProfile(mid: owner.mid),
              let face = profile.card?.face,
              !face.isEmpty
        else { return }
        authorAvatarCache[owner.mid] = face
        updateAuthorAvatar(mid: owner.mid, face: face)
    }

    func preloadPlaybackIfUseful(for video: VideoItem) async {
        guard shouldPreloadPlayback(for: video) else { return }
        await VideoPreloadCenter.shared.preload(video, api: api)
    }

    func cancelPlaybackPreload(for video: VideoItem) async {
        await VideoPreloadCenter.shared.cancel(video)
    }

    private func fetchCurrentPage() async throws -> [VideoItem] {
        switch mode {
        case .recommend:
            return try await api.fetchRecommendFeed(freshIndex: freshIndex)
        case .popular:
            return try await api.fetchPopularVideos(page: popularPage)
        }
    }

    private func fetchFreshPage(replacing previousIDs: [String]) async throws -> [VideoItem] {
        switch mode {
        case .popular:
            return try await api.fetchPopularVideos(page: popularPage)
        case .recommend:
            var lastPage = [VideoItem]()
            for attempt in 0..<5 {
                if attempt > 0 {
                    freshIndex += 1
                }
                let page = try await api.fetchRecommendFeed(freshIndex: freshIndex)
                lastPage = page
                if hasVisibleChange(in: page, comparedTo: previousIDs) {
                    return page
                }
            }
            return lastPage
        }
    }

    private func hasVisibleChange(in page: [VideoItem], comparedTo previousIDs: [String]) -> Bool {
        guard !page.isEmpty else { return false }
        guard !previousIDs.isEmpty else { return true }
        let newFront = page.prefix(8).map(\.id)
        let oldFront = Array(previousIDs.prefix(8))
        return newFront != oldFront
    }

    private func replaceVideos(_ newVideos: [VideoItem], previousIDs: [String]) {
        videos = newVideos
        if newVideos.map(\.id) != previousIDs {
            feedContentVersion += 1
        }
    }

    private func resetCursor() {
        switch mode {
        case .recommend:
            freshIndex = 0
        case .popular:
            popularPage = 1
        }
    }

    private func advanceRefreshCursor() {
        switch mode {
        case .recommend:
            freshIndex += 1
        case .popular:
            popularPage = 1
        }
    }

    private func advanceCursor() {
        switch mode {
        case .recommend:
            freshIndex += 1
        case .popular:
            popularPage += 1
        }
    }

    private func rollbackCursor() {
        switch mode {
        case .recommend:
            freshIndex = max(0, freshIndex - 1)
        case .popular:
            popularPage = max(1, popularPage - 1)
        }
    }

    private func appendUnique(_ more: [VideoItem]) {
        let existing = Set(videos.map(\.id))
        videos.append(contentsOf: more.filter { !existing.contains($0.id) })
    }

    private func updateAuthorAvatar(mid: Int, face: String) {
        videos = videos.map { video in
            guard let owner = video.owner, owner.mid == mid, owner.face?.isEmpty != false else { return video }
            return VideoItem(
                bvid: video.bvid,
                aid: video.aid,
                title: video.title,
                pic: video.pic,
                desc: video.desc,
                duration: video.duration,
                pubdate: video.pubdate,
                owner: VideoOwner(mid: owner.mid, name: owner.name, face: face),
                stat: video.stat,
                cid: video.cid,
                pages: video.pages,
                dimension: video.dimension
            )
        }
    }

    private func shouldPreloadPlayback(for video: VideoItem) -> Bool {
        guard let index = videos.firstIndex(where: { $0.id == video.id }) else { return false }
        let leadingWindow = videos.prefix(8).contains(where: { $0.id == video.id })
        let trailingWindow = index >= max(videos.count - 8, 0)
        return leadingWindow || trailingWindow
    }
}
