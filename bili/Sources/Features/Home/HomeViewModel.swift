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

    var systemImage: String {
        switch self {
        case .recommend:
            return "sparkles"
        case .popular:
            return "flame"
        }
    }
}

private enum HomeFeedSnapshotCache {
    private static let maxAge: TimeInterval = 8 * 60 * 60
    private static let directoryURL = URL.cachesDirectory.appending(
        path: "HomeFeedSnapshots",
        directoryHint: .isDirectory
    )

    static func load(mode: HomeFeedMode, guestModeEnabled: Bool) -> [VideoItem]? {
        if let snapshot = loadDiskSnapshot(mode: mode, guestModeEnabled: guestModeEnabled) {
            return snapshot.videos.map(\.videoItem)
        }
        guard let data = UserDefaults.standard.data(forKey: legacyKey(mode: mode, guestModeEnabled: guestModeEnabled)),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              Date().timeIntervalSince(snapshot.savedAt) < maxAge
        else { return nil }
        save(snapshot: snapshot, mode: mode, guestModeEnabled: guestModeEnabled)
        UserDefaults.standard.removeObject(forKey: legacyKey(mode: mode, guestModeEnabled: guestModeEnabled))
        return snapshot.videos.map(\.videoItem)
    }

    static func save(videos: [VideoItem], mode: HomeFeedMode, guestModeEnabled: Bool) {
        let snapshot = Snapshot(
            savedAt: Date(),
            videos: videos.map(CachedVideo.init(video:))
        )
        save(snapshot: snapshot, mode: mode, guestModeEnabled: guestModeEnabled)
    }

    private static func loadDiskSnapshot(mode: HomeFeedMode, guestModeEnabled: Bool) -> Snapshot? {
        let url = snapshotURL(mode: mode, guestModeEnabled: guestModeEnabled)
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return nil }
        guard Date().timeIntervalSince(snapshot.savedAt) < maxAge else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return snapshot
    }

    private static func save(snapshot: Snapshot, mode: HomeFeedMode, guestModeEnabled: Bool) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try? data.write(
            to: snapshotURL(mode: mode, guestModeEnabled: guestModeEnabled),
            options: [.atomic]
        )
        pruneExpiredSnapshots()
    }

    private static func snapshotURL(mode: HomeFeedMode, guestModeEnabled: Bool) -> URL {
        directoryURL.appending(path: "\(mode.rawValue)-guest-\(guestModeEnabled ? "1" : "0").json")
    }

    private static func legacyKey(mode: HomeFeedMode, guestModeEnabled: Bool) -> String {
        "cc.bili.home.snapshot.\(mode.rawValue).guest-\(guestModeEnabled ? "1" : "0")"
    }

    private static func pruneExpiredSnapshots(now: Date = Date()) {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        for url in urls {
            let modifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modifiedAt, now.timeIntervalSince(modifiedAt) > maxAge * 2 {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    nonisolated private struct Snapshot: Codable {
        let savedAt: Date
        let videos: [CachedVideo]
    }

    nonisolated private struct CachedVideo: Codable {
        let bvid: String
        let aid: Int?
        let title: String
        let pic: String?
        let desc: String?
        let duration: Int?
        let pubdate: Int?
        let owner: CachedOwner?
        let stat: CachedStat?
        let cid: Int?

        init(video: VideoItem) {
            bvid = video.bvid
            aid = video.aid
            title = video.title
            pic = video.pic
            desc = video.desc
            duration = video.duration
            pubdate = video.pubdate
            owner = video.owner.map(CachedOwner.init(owner:))
            stat = video.stat.map(CachedStat.init(stat:))
            cid = video.cid
        }

        @MainActor var videoItem: VideoItem {
            VideoItem(
                bvid: bvid,
                aid: aid,
                title: title,
                pic: pic,
                desc: desc,
                duration: duration,
                pubdate: pubdate,
                owner: owner?.videoOwner,
                stat: stat?.videoStat,
                cid: cid,
                pages: nil,
                dimension: nil
            )
        }
    }

    nonisolated private struct CachedOwner: Codable {
        let mid: Int
        let name: String
        let face: String?

        init(owner: VideoOwner) {
            mid = owner.mid
            name = owner.name
            face = owner.face
        }

        @MainActor var videoOwner: VideoOwner {
            VideoOwner(mid: mid, name: name, face: face)
        }
    }

    nonisolated private struct CachedStat: Codable {
        let view: Int?
        let reply: Int?
        let like: Int?
        let coin: Int?
        let favorite: Int?

        init(stat: VideoStat) {
            view = stat.view
            reply = stat.reply
            like = stat.like
            coin = stat.coin
            favorite = stat.favorite
        }

        var videoStat: VideoStat {
            VideoStat(
                view: view,
                reply: reply,
                like: like,
                coin: coin,
                favorite: favorite
            )
        }
    }
}

private enum HomeGuestRecommendState {
    private static let exposureKey = "cc.bili.home.guestRecommend.exposure.v1"
    private static let cursorKey = "cc.bili.home.guestRecommend.cursor.v1"
    private static let maxExposureAge: TimeInterval = 24 * 60 * 60
    private static let maxExposureCount = 900

    static func recentExposureIDs(now: Date = Date()) -> Set<String> {
        Set(prunedEntries(now: now).map(\.id))
    }

    static func recordExposure(_ videos: [VideoItem], now: Date = Date()) {
        let ids = videos
            .map(\.id)
            .filter { !$0.isEmpty }
        guard !ids.isEmpty else { return }

        let newIDSet = Set(ids)
        var entries = prunedEntries(now: now)
            .filter { !newIDSet.contains($0.id) }
        entries.append(contentsOf: ids.map { ExposureEntry(id: $0, exposedAt: now) })
        entries = Array(entries.suffix(maxExposureCount))
        save(entries)
    }

    static func nextFreshIndex() -> Int {
        max(0, UserDefaults.standard.object(forKey: cursorKey) as? Int ?? 0)
    }

    static func storeNextFreshIndex(after currentIndex: Int) {
        let nextIndex = max(nextFreshIndex(), currentIndex + 1)
        UserDefaults.standard.set(nextIndex, forKey: cursorKey)
    }

    private static func prunedEntries(now: Date = Date()) -> [ExposureEntry] {
        let loadedEntries = loadEntries()
        let entries = loadedEntries
            .filter { now.timeIntervalSince($0.exposedAt) < maxExposureAge }
        let pruned = Array(entries.suffix(maxExposureCount))
        if pruned.count != loadedEntries.count {
            save(pruned)
        }
        return pruned
    }

    private static func loadEntries() -> [ExposureEntry] {
        guard let data = UserDefaults.standard.data(forKey: exposureKey),
              let snapshot = try? JSONDecoder().decode(ExposureSnapshot.self, from: data)
        else { return [] }
        return snapshot.entries
    }

    private static func save(_ entries: [ExposureEntry]) {
        let snapshot = ExposureSnapshot(entries: entries)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: exposureKey)
    }

    nonisolated private struct ExposureSnapshot: Codable {
        let entries: [ExposureEntry]
    }

    nonisolated private struct ExposureEntry: Codable {
        let id: String
        let exposedAt: Date
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

nonisolated private struct HomeVideoCellSignature: Equatable {
    let bvid: String
    let title: String
    let pic: String?
    let duration: Int?
    let pubdate: Int?
    let ownerID: Int?
    let ownerName: String?
    let ownerFace: String?
    let view: Int?
    let width: Int?
    let height: Int?
    let rotate: Int?

    init(video: VideoItem) {
        bvid = video.bvid
        title = video.title
        pic = video.pic
        duration = video.duration
        pubdate = video.pubdate
        ownerID = video.owner?.mid
        ownerName = video.owner?.name
        ownerFace = video.owner?.face
        view = video.stat?.view
        width = video.dimension?.width
        height = video.dimension?.height
        rotate = video.dimension?.rotate
    }
}

private struct HomeVideoCellCacheEntry {
    let signature: HomeVideoCellSignature
    let cell: HomeVideoCellModel
}

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var videos: [VideoItem] = []
    private(set) var videoCells: [HomeVideoCellModel] = []
    @Published var state: LoadingState = .loading
    @Published var mode: HomeFeedMode = .recommend
    @Published var isRefreshing = false
    @Published var isUserRefreshing = false

    private let api: BiliAPIClient
    private let libraryStore: LibraryStore
    private var freshIndex = 0
    private var popularPage = 1
    private var requestRevision = 0
    private var lastUserRefreshDate: Date?
    private var privacyCancellable: AnyCancellable?
    private var imagePrefetchTask: Task<Void, Never>?
    private var playbackPreloadTask: Task<Void, Never>?
    private var videoCellCache: [String: HomeVideoCellCacheEntry] = [:]

    private var usesGuestRecommendDiversity: Bool {
        mode == .recommend && libraryStore.guestModeEnabled
    }

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
        updateFeed([])
        state = .loading
        await refresh(resetCursor: true)
    }

    func switchMode(_ newMode: HomeFeedMode) async {
        guard mode != newMode else { return }
        mode = newMode
        updateFeed([])
        restoreCachedVideosIfAvailable()
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
        isUserRefreshing = true
        defer {
            isUserRefreshing = false
        }
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
            if previousVideos.isEmpty {
                await prewarmInitialImagesBeforePublishing(refreshedVideos)
            }
            replaceVideos(refreshedVideos, previousVideos: previousVideos)
            persistCurrentSnapshot()
            state = .loaded
        } catch {
            guard revision == requestRevision else { return }
            state = .failed(error.localizedDescription)
        }
    }

    func reloadForGuestModeChange() async {
        guard mode == .recommend else { return }
        updateFeed([])
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
            if usesGuestRecommendDiversity {
                return try await fetchGuestRecommendPage(
                    excluding: Set(videos.map(\.id)),
                    minimumFreshCount: 10,
                    maximumAttempts: 4
                )
            }
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
            if usesGuestRecommendDiversity {
                return try await fetchGuestRecommendPage(
                    excluding: Set(previousIDs),
                    minimumFreshCount: previousIDs.isEmpty ? 14 : 10,
                    maximumAttempts: 5
                )
            }
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

    private func fetchGuestRecommendPage(
        excluding excludedIDs: Set<String>,
        minimumFreshCount: Int,
        maximumAttempts: Int
    ) async throws -> [VideoItem] {
        var exposureIDs = HomeGuestRecommendState.recentExposureIDs()
        exposureIDs.formUnion(excludedIDs)

        var freshVideos = [VideoItem]()
        var freshIDs = Set<String>()
        var fallbackVideos = [VideoItem]()
        var fallbackIDs = Set<String>()
        var lastRawPage = [VideoItem]()

        for attempt in 0..<maximumAttempts {
            if attempt > 0 {
                freshIndex += 1
            }
            let page = try await api.fetchRecommendFeed(freshIndex: freshIndex)
            lastRawPage = page

            for video in page where !video.id.isEmpty {
                if !excludedIDs.contains(video.id),
                   fallbackIDs.insert(video.id).inserted {
                    fallbackVideos.append(video)
                }
                if !exposureIDs.contains(video.id),
                   freshIDs.insert(video.id).inserted {
                    freshVideos.append(video)
                    exposureIDs.insert(video.id)
                }
            }

            if freshVideos.count >= minimumFreshCount {
                break
            }
        }

        HomeGuestRecommendState.storeNextFreshIndex(after: freshIndex)

        guard !freshVideos.isEmpty else {
            return fallbackVideos.isEmpty ? lastRawPage : fallbackVideos
        }
        let targetCount = max(minimumFreshCount, min(20, fallbackVideos.count))
        guard freshVideos.count < targetCount else {
            return freshVideos
        }

        var merged = freshVideos
        var mergedIDs = Set(freshVideos.map(\.id))
        for video in fallbackVideos where mergedIDs.insert(video.id).inserted {
            merged.append(video)
            if merged.count >= targetCount {
                break
            }
        }
        return merged
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
        updateFeed(mergedVideos)
        recordGuestRecommendExposure(mergedVideos)
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
            freshIndex = usesGuestRecommendDiversity ? HomeGuestRecommendState.nextFreshIndex() : 0
        case .popular:
            popularPage = 1
        }
    }

    private func advanceRefreshCursor() {
        switch mode {
        case .recommend:
            if usesGuestRecommendDiversity {
                freshIndex = max(freshIndex + 1, HomeGuestRecommendState.nextFreshIndex())
            } else {
                freshIndex += 1
            }
        case .popular:
            popularPage = 1
        }
    }

    private func advanceCursor() {
        switch mode {
        case .recommend:
            if usesGuestRecommendDiversity {
                freshIndex = max(freshIndex + 1, HomeGuestRecommendState.nextFreshIndex())
            } else {
                freshIndex += 1
            }
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
        guard !unique.isEmpty else { return }
        updateFeed(videos + unique)
        recordGuestRecommendExposure(unique)
        persistCurrentSnapshot()
        scheduleImagePrefetch(for: Array(unique.prefix(8)))
        schedulePlaybackPreload(for: unique, initialDelay: 1.2)
    }

    private func restoreCachedVideosIfAvailable() {
        guard videos.isEmpty else { return }
        guard let cachedVideos = HomeFeedSnapshotCache.load(mode: mode, guestModeEnabled: libraryStore.guestModeEnabled),
              !cachedVideos.isEmpty
        else { return }
        updateFeed(cachedVideos)
        state = .loaded
        scheduleImagePrefetch(for: Array(cachedVideos.prefix(8)))
    }

    private func updateFeed(_ newVideos: [VideoItem]) {
        var nextCache = [String: HomeVideoCellCacheEntry]()
        nextCache.reserveCapacity(newVideos.count)
        let cells = newVideos.map { video in
            let signature = HomeVideoCellSignature(video: video)
            if let cached = videoCellCache[video.id], cached.signature == signature {
                nextCache[video.id] = cached
                return cached.cell
            }
            let cell = HomeVideoCellModel(video: video)
            nextCache[video.id] = HomeVideoCellCacheEntry(signature: signature, cell: cell)
            return cell
        }
        videoCells = cells
        videoCellCache = nextCache
        videos = newVideos
    }

    private func persistCurrentSnapshot() {
        HomeFeedSnapshotCache.save(
            videos: Array(videos.prefix(48)),
            mode: mode,
            guestModeEnabled: libraryStore.guestModeEnabled
        )
    }

    private func recordGuestRecommendExposure(_ videos: [VideoItem]) {
        guard usesGuestRecommendDiversity else { return }
        HomeGuestRecommendState.recordExposure(Array(videos.prefix(80)))
    }

    private func scheduleImagePrefetch(for videos: [VideoItem]) {
        imagePrefetchTask?.cancel()
        let environment = PlaybackEnvironment.current
        let prefetchLimit = environment.shouldPreferConservativePlayback ? 4 : 5
        let prefetchPlan = imagePrefetchPlan(for: videos, limit: prefetchLimit)

        guard !prefetchPlan.coverSources.isEmpty || !prefetchPlan.avatarSources.isEmpty else { return }
        let coverSourcesToPrefetch = prefetchPlan.coverSources
        let avatarSourcesToPrefetch = prefetchPlan.avatarSources
        let coverTargetPixelSize = prefetchPlan.coverTargetPixelSize
        let avatarTargetPixelSize = prefetchPlan.avatarTargetPixelSize
        imagePrefetchTask = Task(priority: .utility) {
            async let coverPrefetch: Void = RemoteImageCache.shared.prefetch(
                coverSourcesToPrefetch,
                targetPixelSize: coverTargetPixelSize,
                maximumConcurrentLoads: 1
            )
            async let avatarPrefetch: Void = RemoteImageCache.shared.prefetch(
                avatarSourcesToPrefetch,
                targetPixelSize: avatarTargetPixelSize,
                maximumConcurrentLoads: 1
            )
            _ = await (coverPrefetch, avatarPrefetch)
        }
    }

    private func prewarmInitialImagesBeforePublishing(_ videos: [VideoItem]) async {
        let prefetchPlan = imagePrefetchPlan(for: videos, limit: 3)
        guard !prefetchPlan.coverSources.isEmpty || !prefetchPlan.avatarSources.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                async let coverPrefetch: Void = RemoteImageCache.shared.prefetch(
                    prefetchPlan.coverSources,
                    targetPixelSize: prefetchPlan.coverTargetPixelSize,
                    maximumConcurrentLoads: 1
                )
                async let avatarPrefetch: Void = RemoteImageCache.shared.prefetch(
                    prefetchPlan.avatarSources,
                    targetPixelSize: prefetchPlan.avatarTargetPixelSize,
                    maximumConcurrentLoads: 1
                )
                _ = await (coverPrefetch, avatarPrefetch)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 320_000_000)
            }
            _ = await group.next()
            group.cancelAll()
        }
    }

    private func imagePrefetchPlan(
        for videos: [VideoItem],
        limit: Int
    ) -> (coverSources: [RemoteImageSource], avatarSources: [RemoteImageSource], coverTargetPixelSize: Int, avatarTargetPixelSize: Int) {
        var seenCovers = Set<String>()
        var seenAvatars = Set<String>()
        var coverSources = [RemoteImageSource]()
        var avatarSources = [RemoteImageSource]()
        let coverTargetPixelSize: Int
        let avatarTargetPixelSize: Int
        switch libraryStore.homeFeedLayout {
        case .singleColumn:
            coverTargetPixelSize = 720
            avatarTargetPixelSize = 64
        case .doubleColumn:
            coverTargetPixelSize = 480
            avatarTargetPixelSize = 48
        }

        for video in videos.prefix(limit) {
            let coverHeight = Int(Double(coverTargetPixelSize) * 9.0 / 16.0)
            if let source = video.pic?.normalizedBiliURL(),
               let url = URL(string: source.biliCoverThumbnailURL(width: coverTargetPixelSize, height: coverHeight)),
               seenCovers.insert(source).inserted {
                coverSources.append(RemoteImageSource(url: url, fallbackURL: URL(string: source)))
            }
            if let source = video.owner?.face?.normalizedBiliURL(),
               let url = URL(string: source.biliAvatarThumbnailURL(size: avatarTargetPixelSize)),
               seenAvatars.insert(source).inserted {
                avatarSources.append(RemoteImageSource(url: url, fallbackURL: URL(string: source)))
            }
        }

        return (coverSources, avatarSources, coverTargetPixelSize, avatarTargetPixelSize)
    }

    private func schedulePlaybackPreload(for videos: [VideoItem], initialDelay: TimeInterval) {
        playbackPreloadTask?.cancel()
        let playbackAdaptationProfile = PlayerPerformanceStore.shared.playbackAdaptationProfile(
            isEnabled: libraryStore.isPlaybackAutoOptimizationEnabled
        )
        let candidateLimit = max(0, min(1, playbackAdaptationProfile.backgroundRoutePlanPreloadLimit))
        guard candidateLimit > 0 else {
            playbackPreloadTask = nil
            return
        }
        let candidates = Array(videos
            .filter { $0.cid != nil && !$0.bvid.isEmpty }
            .prefix(candidateLimit))
        guard !candidates.isEmpty else {
            playbackPreloadTask = nil
            return
        }

        let preferredQuality = libraryStore.preferredVideoQuality
        let cdnPreference = libraryStore.effectivePlaybackCDNPreference
        playbackPreloadTask = Task(priority: .background) { [api, cdnPreference] in
            try? await Task.sleep(nanoseconds: UInt64((initialDelay + 0.4) * 1_000_000_000))
            for (index, video) in candidates.enumerated() {
                guard !Task.isCancelled else { return }
                await VideoPreloadCenter.shared.updatePlaybackPreferences(
                    preferredQuality: preferredQuality,
                    cdnPreference: cdnPreference,
                    playbackAdaptationProfile: playbackAdaptationProfile
                )
                await VideoPreloadCenter.shared.preloadPlayInfo(
                    video,
                    api: api,
                    preferredQuality: preferredQuality,
                    cdnPreference: cdnPreference,
                    priority: .background,
                    warmsMedia: true,
                    mediaWarmupMode: .routePlanOnly,
                    mediaWarmupDelay: 0.35,
                    playbackAdaptationProfile: playbackAdaptationProfile
                )
                if index < candidates.count - 1 {
                    try? await Task.sleep(nanoseconds: 650_000_000)
                }
            }
        }
    }
}
