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

struct HomeVideoCellModel: Identifiable, Equatable {
    let id: String
    let video: VideoItem
    let display: VideoCardDisplayModel

    init(video: VideoItem) {
        self.id = video.id
        self.video = video
        self.display = VideoCardDisplayModel(video: video)
    }
}

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var videos: [VideoItem] = []
    private(set) var videoDisplays: [VideoCardDisplayModel] = []
    private(set) var videoCells: [HomeVideoCellModel] = []
    @Published var state: LoadingState = .idle
    @Published var mode: HomeFeedMode = .recommend
    @Published var isRefreshing = false

    private let api: BiliAPIClient
    private let libraryStore: LibraryStore
    private var freshIndex = 0
    private var popularPage = 1
    private var requestRevision = 0
    private var lastUserRefreshDate: Date?
    private var privacyCancellable: AnyCancellable?
    private var imagePrefetchTask: Task<Void, Never>?
    private var playbackPreloadTask: Task<Void, Never>?

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

    deinit {
        imagePrefetchTask?.cancel()
        playbackPreloadTask?.cancel()
    }

    func loadInitial() async {
        guard videos.isEmpty else { return }
        await refresh(resetCursor: true)
    }

    func switchMode(_ newMode: HomeFeedMode) async {
        guard mode != newMode else { return }
        mode = newMode
        videoCells = []
        videoDisplays = []
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
        let previousVideos = videos
        let previousIDs = previousVideos.map(\.id)
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
            replaceVideos(refreshedVideos, previousVideos: previousVideos)
            state = .loaded
        } catch {
            guard revision == requestRevision else { return }
            state = .failed(error.localizedDescription)
        }
    }

    func reloadForGuestModeChange() async {
        guard mode == .recommend else { return }
        videoCells = []
        videoDisplays = []
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

    private func replaceVideos(_ newVideos: [VideoItem], previousVideos: [VideoItem]) {
        let mergedVideos = mergedRefreshVideos(newVideos, previousVideos: previousVideos)
        let mergedCells = mergedVideos.map(HomeVideoCellModel.init(video:))
        videoCells = mergedCells
        videoDisplays = mergedCells.map(\.display)
        videos = mergedVideos
        scheduleImagePrefetch(for: mergedVideos)
        schedulePlaybackPreload(for: newVideos, initialDelay: 0.75)
    }

    private func mergedRefreshVideos(_ fresh: [VideoItem], previousVideos: [VideoItem]) -> [VideoItem] {
        guard mode == .recommend, !fresh.isEmpty, !previousVideos.isEmpty else {
            return fresh
        }
        var seen = Set(fresh.map(\.id))
        let retainedTail = previousVideos
            .prefix(50)
            .filter { seen.insert($0.id).inserted }
        return fresh + retainedTail
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
        let unique = more.filter { !existing.contains($0.id) }
        let newCells = unique.map(HomeVideoCellModel.init(video:))
        videoCells.append(contentsOf: newCells)
        videoDisplays.append(contentsOf: newCells.map(\.display))
        videos.append(contentsOf: unique)
        scheduleImagePrefetch(for: Array(unique.prefix(8)))
        schedulePlaybackPreload(for: unique, initialDelay: 1.2)
    }

    private func scheduleImagePrefetch(for videos: [VideoItem]) {
        imagePrefetchTask?.cancel()
        var seenCovers = Set<URL>()
        var seenAvatars = Set<URL>()
        var coverURLs = [URL]()
        var avatarURLs = [URL]()
        let usesSingleColumnArtwork = libraryStore.homeFeedLayout == .singleColumn
        let coverTargetPixelSize = usesSingleColumnArtwork ? 760 : 540
        let avatarTargetPixelSize = usesSingleColumnArtwork ? 64 : 48

        for video in videos.prefix(10) {
            if let url = video.pic.flatMap({ URL(string: $0.biliCoverThumbnailURL(width: 480, height: 270)) }),
               seenCovers.insert(url).inserted {
                coverURLs.append(url)
            }
            if let url = video.owner?.face.flatMap({ URL(string: $0.biliAvatarThumbnailURL(size: 48)) }),
               seenAvatars.insert(url).inserted {
                avatarURLs.append(url)
            }
        }

        guard !coverURLs.isEmpty || !avatarURLs.isEmpty else { return }
        imagePrefetchTask = Task(priority: .utility) {
            async let coverPrefetch: Void = RemoteImageCache.shared.prefetch(
                coverURLs,
                targetPixelSize: coverTargetPixelSize,
                maximumConcurrentLoads: 2
            )
            async let avatarPrefetch: Void = RemoteImageCache.shared.prefetch(
                avatarURLs,
                targetPixelSize: avatarTargetPixelSize,
                maximumConcurrentLoads: 1
            )
            _ = await (coverPrefetch, avatarPrefetch)
        }
    }

    private func schedulePlaybackPreload(for videos: [VideoItem], initialDelay: TimeInterval) {
        playbackPreloadTask?.cancel()
        guard !PlaybackEnvironment.current.shouldPreferConservativePlayback else {
            playbackPreloadTask = nil
            return
        }
        let candidates = Array(videos
            .filter { $0.cid != nil && !$0.bvid.isEmpty }
            .prefix(mode == .recommend ? 2 : 1))
        guard !candidates.isEmpty else {
            playbackPreloadTask = nil
            return
        }

        let preferredQuality = libraryStore.preferredVideoQuality
        let cdnPreference = libraryStore.playbackCDNPreference
        playbackPreloadTask = Task(priority: .background) { [api, cdnPreference] in
            try? await Task.sleep(nanoseconds: UInt64(initialDelay * 1_000_000_000))
            for (index, video) in candidates.enumerated() {
                guard !Task.isCancelled else { return }
                await VideoPreloadCenter.shared.updatePlaybackPreferences(
                    preferredQuality: preferredQuality,
                    cdnPreference: cdnPreference
                )
                await VideoPreloadCenter.shared.preloadPlayInfo(
                    video,
                    api: api,
                    preferredQuality: preferredQuality,
                    cdnPreference: cdnPreference,
                    priority: .background
                )
                if index < candidates.count - 1 {
                    try? await Task.sleep(nanoseconds: 650_000_000)
                }
            }
        }
    }
}
