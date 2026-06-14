import Foundation
import OSLog
import QuartzCore

nonisolated final class BiliNetworkMetricsRecorder: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let logger = Logger(subsystem: "cc.bili", category: "NetworkMetrics")

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didFinishCollecting metrics: URLSessionTaskMetrics
    ) {
        guard let transaction = metrics.transactionMetrics.last,
              let url = transaction.request.url
        else { return }

        let host = url.host ?? "-"
        let path = Self.metricsPath(for: url)
        let duration = max(0, metrics.taskInterval.duration)
        let protocolName = transaction.networkProtocolName ?? "-"
        let dnsMilliseconds = Self.intervalMilliseconds(
            from: transaction.domainLookupStartDate,
            to: transaction.domainLookupEndDate
        )
        let connectMilliseconds = Self.intervalMilliseconds(
            from: transaction.connectStartDate,
            to: transaction.connectEndDate
        )
        let tlsMilliseconds = Self.intervalMilliseconds(
            from: transaction.secureConnectionStartDate,
            to: transaction.secureConnectionEndDate
        )
        let ttfbMilliseconds = Self.intervalMilliseconds(
            from: transaction.requestStartDate,
            to: transaction.responseStartDate
        )
        let totalMilliseconds = Int((duration * 1000).rounded())
        let reused = transaction.isReusedConnection ? "reuse" : "new"
        let message = "host=\(host) path=\(path) proto=\(protocolName) \(reused) total=\(totalMilliseconds)ms dns=\(dnsMilliseconds)ms conn=\(connectMilliseconds)ms tls=\(tlsMilliseconds)ms ttfb=\(ttfbMilliseconds)ms"

        logger.info("\(message, privacy: .public)")

        guard let metricsID = Self.metricsID(for: url) else { return }
        Task { @MainActor in
            PlayerPerformanceStore.shared.record(
                .network,
                metricsID: metricsID,
                title: nil,
                message: message
            )
        }
    }

    private nonisolated static func intervalMilliseconds(from start: Date?, to end: Date?) -> Int {
        guard let start, let end else { return 0 }
        return max(0, Int((end.timeIntervalSince(start) * 1000).rounded()))
    }

    private nonisolated static func metricsPath(for url: URL) -> String {
        guard url.host?.contains("bilibili.com") == true else {
            return url.path.isEmpty ? "/" : url.path
        }
        if url.path == "/x/player/playurl" || url.path == "/x/player/wbi/playurl" {
            return "playurl"
        }
        if url.path == "/x/web-interface/view" {
            return "detail"
        }
        if url.path == "/x/web-interface/archive/related" {
            return "related"
        }
        if url.path == "/x/v2/reply/main" {
            return "comments"
        }
        if url.path == "/video/" || url.path.contains("/video/") {
            return "webpage"
        }
        return url.path.isEmpty ? "/" : url.path
    }

    private nonisolated static func metricsID(for url: URL) -> String? {
        if let bvid = queryValue("bvid", in: url), !bvid.isEmpty {
            return bvid
        }
        let path = url.path
        if let range = path.range(of: #"BV[A-Za-z0-9]+"#, options: .regularExpression) {
            return String(path[range])
        }
        return nil
    }

    private nonisolated static func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
    }
}

nonisolated struct LiveDanmakuClientContext: Sendable {
    let uid: Int
    let buvid: String
    let cookieHeader: String
    let headers: [String: String]
}

nonisolated final class BiliAPIClient {
    private let baseURL = URL(string: "https://api.bilibili.com")!
    private let appURL = URL(string: "https://app.bilibili.com")!
    private let passportURL = URL(string: "https://passport.bilibili.com")!
    private let liveURL = URL(string: "https://api.live.bilibili.com")!
    private let commentURL = URL(string: "https://comment.bilibili.com")!
    private static let supplementalQualityLadder = [127, 126, 125, 120, 116, 112, 80, 74, 64, 32, 16, 6]
    private static let mobileUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    private static let webUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    private let session: URLSession
    private let sessionStore: SessionStore
    private let libraryStore: LibraryStore
    private let playURLCache: PlayURLCache
    private let state = BiliAPIClientState()

    private struct RequestSnapshot: Sendable {
        let cookieHeader: String
        let anonymousCookieHeader: String
        let isLoggedIn: Bool
        let csrfToken: String?
        let currentUserMID: Int?
        let preferredVideoQuality: Int?
        let playbackStreamSourcePreference: PlaybackStreamSourcePreference
        let homeRecommendFeedSourcePreference: HomeRecommendFeedSourcePreference
        let guestModeEnabled: Bool
    }

    init(
        session: URLSession = .shared,
        sessionStore: SessionStore,
        libraryStore: LibraryStore,
        playURLCache: PlayURLCache = .shared
    ) {
        self.session = session
        self.sessionStore = sessionStore
        self.libraryStore = libraryStore
        self.playURLCache = playURLCache
    }

    @MainActor
    private func requestSnapshot() -> RequestSnapshot {
        RequestSnapshot(
            cookieHeader: sessionStore.cookieHeader(),
            anonymousCookieHeader: sessionStore.anonymousCookieHeader(),
            isLoggedIn: sessionStore.isLoggedIn,
            csrfToken: sessionStore.csrfToken(),
            currentUserMID: sessionStore.user?.mid,
            preferredVideoQuality: libraryStore.preferredVideoQuality,
            playbackStreamSourcePreference: libraryStore.playbackStreamSourcePreference,
            homeRecommendFeedSourcePreference: libraryStore.homeRecommendFeedSourcePreference,
            guestModeEnabled: libraryStore.guestModeEnabled
        )
    }

    private func cookieHeader() async -> String {
        let snapshot = await requestSnapshot()
        return snapshot.cookieHeader
    }

    private func anonymousCookieHeader() async -> String {
        let snapshot = await requestSnapshot()
        return snapshot.anonymousCookieHeader
    }

    private func preferredVideoQuality() async -> Int? {
        let snapshot = await requestSnapshot()
        return snapshot.preferredVideoQuality
    }

    private func playbackStreamSourcePreference() async -> PlaybackStreamSourcePreference {
        let snapshot = await requestSnapshot()
        return snapshot.playbackStreamSourcePreference
    }

    private func isLoggedIn() async -> Bool {
        let snapshot = await requestSnapshot()
        return snapshot.isLoggedIn
    }

    func prewarmPlaybackSigningKeys() async {
        _ = try? await fetchWBIKeys(priority: .utility)
    }

    func refreshPlaybackSigningKeys() async throws -> WBIKeys {
        await state.clearWBIKeys()
        return try await fetchWBIKeys(priority: .userInitiated)
    }

    func prewarmStartupResources() async {
        async let keys: Void = prewarmPlaybackSigningKeys()
        async let nav: NavUserInfo? = try? fetchNavUser()
        _ = await (keys, nav)
    }

    func fetchRecommendFeed(freshIndex: Int = 0) async throws -> [VideoItem] {
        let snapshot = await requestSnapshot()
        let feedSource = snapshot.homeRecommendFeedSourcePreference
        let taskKey = "recommend|\(feedSource.rawValue)|\(freshIndex)|guest-\(snapshot.guestModeEnabled ? "1" : "0")"
        if let task = await state.videoListTask(for: taskKey) {
            return try await task.value
        }
        let task = Task<[VideoItem], Error>(priority: .userInitiated) { [self] in
            switch feedSource {
            case .web:
                return try await fetchWebRecommendFeed(freshIndex: freshIndex)
            case .app:
                return try await fetchAppRecommendFeed(freshIndex: freshIndex, preferredVideoQuality: snapshot.preferredVideoQuality)
            }
        }
        await state.setVideoListTask(task, for: taskKey)
        do {
            let videos = try await task.value
            await state.clearVideoListTask(for: taskKey)
            return videos
        } catch {
            await state.clearVideoListTask(for: taskKey)
            throw error
        }
    }

    private func fetchWebRecommendFeed(freshIndex: Int) async throws -> [VideoItem] {
        let keys = try await fetchWBIKeys(priority: .userInitiated)
        let signed = WBISigner.sign([
            "version": "1",
            "homepage_ver": "1",
            "feed_version": "V8",
            "ps": "20",
            "fresh_idx": String(freshIndex),
            "brush": String(freshIndex),
            "fresh_idx_1h": String(freshIndex),
            "fresh_type": "4"
        ], keys: keys)

        let response: BiliResponse<RecommendFeedData> = try await get(
            base: baseURL,
            path: "/x/web-interface/wbi/index/top/feed/rcmd",
            query: signed,
            cookieHeader: await guestModeCookieHeader(),
            cachePolicy: .reloadIgnoringLocalCacheData,
            responseCachePolicy: .brief
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        return response.payload?.feedItems.compactMap { $0.asVideoItem() } ?? []
    }

    private func fetchAppRecommendFeed(freshIndex: Int, preferredVideoQuality: Int?) async throws -> [VideoItem] {
        let requestedIndex = freshIndex <= 0 ? 0 : await state.appRecommendFeedIndex(defaulting: freshIndex)
        let response: BiliResponse<RecommendFeedData> = try await get(
            base: appURL,
            path: "/x/v2/feed/index",
            query: [
                "idx": String(requestedIndex),
                "flush": requestedIndex == 0 ? "1" : "0",
                "column": "4",
                "pull": requestedIndex == 0 ? "1" : "0",
                "device": "phone",
                "mobi_app": "iphone",
                "platform": "ios",
                "build": "70000100",
                "fnval": "4048",
                "qn": String(preferredVideoQuality ?? 112),
                "fourk": "1"
            ],
            referer: "https://app.bilibili.com",
            userAgent: Self.mobileUserAgent,
            cookieHeader: await guestModeCookieHeader(),
            cachePolicy: .reloadIgnoringLocalCacheData,
            responseCachePolicy: .brief
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard let payload = response.payload else { return [] }
        await state.setAppRecommendFeedIndex(payload.appNextIndex(after: requestedIndex))
        let videos = payload.feedItems.compactMap { $0.asVideoItem() }
        return await hydrateAppRecommendFeedIfNeeded(videos)
    }

    private func hydrateAppRecommendFeedIfNeeded(_ videos: [VideoItem]) async -> [VideoItem] {
        let hydrationCandidates = Array(videos.enumerated().filter { _, video in
            video.aid != nil && (video.pubdate == nil || video.owner?.face == nil)
        }.prefix(10))
        guard !hydrationCandidates.isEmpty else { return videos }

        let hydratedPairs = await withTaskGroup(of: (Int, VideoItem)?.self) { group in
            for (index, video) in hydrationCandidates {
                guard let aid = video.aid else { continue }
                group.addTask { [self] in
                    guard let fullDetail = try? await fetchVideoDetail(aid: aid) else { return nil }
                    return (index, video.mergingFilledValues(from: fullDetail))
                }
            }

            var pairs = [(Int, VideoItem)]()
            for await pair in group {
                if let pair {
                    pairs.append(pair)
                }
            }
            return pairs
        }

        guard !hydratedPairs.isEmpty else { return videos }
        var mergedVideos = videos
        for (index, video) in hydratedPairs where mergedVideos.indices.contains(index) {
            mergedVideos[index] = video
        }
        return mergedVideos
    }

    func fetchPopularVideos(page: Int = 1) async throws -> [VideoItem] {
        let taskKey = "popular|\(page)"
        if let task = await state.videoListTask(for: taskKey) {
            return try await task.value
        }
        let task = Task<[VideoItem], Error>(priority: .userInitiated) { [self] in
            let response: BiliResponse<BiliPage<VideoItem>> = try await get(
                base: baseURL,
                path: "/x/web-interface/popular",
                query: [
                    "pn": String(page),
                    "ps": "20"
                ],
                responseCachePolicy: .brief
            )
            guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
            return response.payload?.list ?? []
        }
        await state.setVideoListTask(task, for: taskKey)
        do {
            let videos = try await task.value
            await state.clearVideoListTask(for: taskKey)
            return videos
        } catch {
            await state.clearVideoListTask(for: taskKey)
            throw error
        }
    }

    func fetchVideoDetail(bvid: String) async throws -> VideoItem {
        if let task = await state.videoDetailTask(for: bvid) {
            return try await task.value
        }
        let task = Task<VideoItem, Error>(priority: .userInitiated) { [self] in
            let response: BiliResponse<VideoItem> = try await get(
                base: baseURL,
                path: "/x/web-interface/view",
                query: ["bvid": bvid],
                responseCachePolicy: .detail
            )
            guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
            guard let item = response.payload else { throw BiliAPIError.missingPayload }
            return item
        }
        await state.setVideoDetailTask(task, for: bvid)
        do {
            let item = try await task.value
            await state.clearVideoDetailTask(for: bvid)
            return item
        } catch {
            await state.clearVideoDetailTask(for: bvid)
            throw error
        }
    }

    func fetchVideoDetail(aid: Int) async throws -> VideoItem {
        let taskKey = "aid:\(aid)"
        if let task = await state.videoDetailTask(for: taskKey) {
            return try await task.value
        }
        let task = Task<VideoItem, Error>(priority: .userInitiated) { [self] in
            let response: BiliResponse<VideoItem> = try await get(
                base: baseURL,
                path: "/x/web-interface/view",
                query: ["aid": String(aid)],
                responseCachePolicy: .detail
            )
            guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
            guard let item = response.payload else { throw BiliAPIError.missingPayload }
            return item
        }
        await state.setVideoDetailTask(task, for: taskKey)
        do {
            let item = try await task.value
            await state.clearVideoDetailTask(for: taskKey)
            return item
        } catch {
            await state.clearVideoDetailTask(for: taskKey)
            throw error
        }
    }

    func fetchVideoRelated(bvid: String) async throws -> [VideoItem] {
        let response: BiliResponse<[VideoItem]> = try await get(
            base: baseURL,
            path: "/x/web-interface/archive/related",
            query: [
                "bvid": bvid,
                "pn": "1",
                "ps": "40"
            ],
            userAgent: Self.webUserAgent,
            cookieHeader: await guestModeCookieHeader(),
            cachePolicy: .reloadIgnoringLocalCacheData,
            responseCachePolicy: .short
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        return response.payload ?? []
    }

    func fetchDanmaku(cid: Int) async throws -> [DanmakuItem] {
        if let cached = await SubtitleDanmakuResourceCache.shared.danmaku(for: cid, segmentIndex: 0) {
            return cached
        }

        return try await ResourceRequestLimiter.shared.runDanmaku { [self] in
            if let cached = await SubtitleDanmakuResourceCache.shared.danmaku(for: cid, segmentIndex: 0) {
                return cached
            }

            var request = try await makeRequest(
                base: commentURL,
                path: "/\(cid).xml",
                query: [:],
                referer: "https://www.bilibili.com",
                userAgent: Self.webUserAgent,
                cookieHeader: await guestModeCookieHeader(),
                cachePolicy: .returnCacheDataElseLoad
            )
            request.networkServiceType = .responsiveData
            request.timeoutInterval = 8
            request.setValue("application/xml,text/xml,*/*", forHTTPHeaderField: "Accept")

            let (data, response) = try await data(for: request, priority: .utility)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode)
            else {
                throw BiliAPIError.emptyData
            }
            guard !data.isEmpty else { throw BiliAPIError.emptyData }

            let items = try DanmakuXMLParser(cid: cid).parse(data: data)
            await SubtitleDanmakuResourceCache.shared.storeDanmaku(items, for: cid, segmentIndex: 0)
            return items
        }
    }

    func fetchDanmakuSegment(cid: Int, segmentIndex: Int) async throws -> [DanmakuItem] {
        let normalizedSegmentIndex = max(1, segmentIndex)
        if let cached = await SubtitleDanmakuResourceCache.shared.danmaku(
            for: cid,
            segmentIndex: normalizedSegmentIndex
        ) {
            return cached
        }

        return try await ResourceRequestLimiter.shared.runDanmaku { [self] in
            if let cached = await SubtitleDanmakuResourceCache.shared.danmaku(
                for: cid,
                segmentIndex: normalizedSegmentIndex
            ) {
                return cached
            }

            var request = try await makeRequest(
                base: baseURL,
                path: "/x/v2/dm/web/seg.so",
                query: [
                    "type": "1",
                    "oid": String(cid),
                    "segment_index": String(normalizedSegmentIndex)
                ],
                referer: "https://www.bilibili.com",
                userAgent: Self.webUserAgent,
                cookieHeader: await guestModeCookieHeader(),
                cachePolicy: .returnCacheDataElseLoad
            )
            request.networkServiceType = .responsiveData
            request.timeoutInterval = 8
            request.setValue("application/octet-stream,*/*", forHTTPHeaderField: "Accept")

            let (data, response) = try await data(for: request, priority: .utility)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode)
            else {
                throw BiliAPIError.emptyData
            }

            let items = try DanmakuSegmentProtobufParser(
                cid: cid,
                segmentIndex: normalizedSegmentIndex
            )
            .parse(data: data)
            await SubtitleDanmakuResourceCache.shared.storeDanmaku(
                items,
                for: cid,
                segmentIndex: normalizedSegmentIndex
            )
            return items
        }
    }

    func fetchUploaderProfile(mid: Int) async throws -> UploaderProfile {
        if let task = await state.uploaderProfileTask(for: mid) {
            return try await task.value
        }
        let task = Task<UploaderProfile, Error>(priority: .utility) { [self] in
            let response: BiliResponse<UploaderProfile> = try await get(
                base: baseURL,
                path: "/x/web-interface/card",
                query: ["mid": String(mid)],
                responseCachePolicy: .detail
            )
            guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
            guard let profile = response.payload else { throw BiliAPIError.missingPayload }
            return profile
        }
        await state.setUploaderProfileTask(task, for: mid)
        do {
            let profile = try await task.value
            await state.clearUploaderProfileTask(for: mid)
            return profile
        } catch {
            await state.clearUploaderProfileTask(for: mid)
            throw error
        }
    }

    func fetchVideoInteractionState(aid: Int) async throws -> VideoInteractionState {
        guard await isLoggedIn() else {
            throw BiliAPIError.missingSESSDATA
        }

        async let like: BiliResponse<Int> = get(
            base: baseURL,
            path: "/x/web-interface/archive/has/like",
            query: ["aid": String(aid)],
            priority: .utility
        )
        async let coin: BiliResponse<VideoCoinState> = get(
            base: baseURL,
            path: "/x/web-interface/archive/coins",
            query: ["aid": String(aid)],
            priority: .utility
        )
        async let favorite: BiliResponse<VideoFavoriteState> = get(
            base: baseURL,
            path: "/x/v2/fav/video/favoured",
            query: ["aid": String(aid)],
            priority: .utility
        )

        let (likeResponse, coinResponse, favoriteResponse) = try await (like, coin, favorite)

        guard likeResponse.code == 0 else { throw BiliAPIError.api(code: likeResponse.code, message: likeResponse.displayMessage) }
        guard coinResponse.code == 0 else { throw BiliAPIError.api(code: coinResponse.code, message: coinResponse.displayMessage) }
        guard favoriteResponse.code == 0 else { throw BiliAPIError.api(code: favoriteResponse.code, message: favoriteResponse.displayMessage) }

        return VideoInteractionState(
            isLiked: (likeResponse.payload ?? 0) == 1,
            coinCount: coinResponse.payload?.multiply ?? 0,
            isFavorited: favoriteResponse.payload?.favoured ?? false,
            isFollowing: false
        )
    }

    func toggleVideoLike(aid: Int, liked: Bool) async throws {
        let csrf = try await requireCSRF()
        let response: BiliResponse<EmptyBiliPayload> = try await postForm(
            base: baseURL,
            path: "/x/web-interface/archive/like",
            body: [
                "aid": String(aid),
                "like": liked ? "1" : "2",
                "csrf": csrf,
                "cross_domain": "true",
                "source": "web_normal",
                "ga": "1"
            ]
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
    }

    func addVideoCoin(aid: Int, selectLike: Bool = false) async throws {
        let csrf = try await requireCSRF()
        let response: BiliResponse<EmptyBiliPayload> = try await postForm(
            base: baseURL,
            path: "/x/web-interface/coin/add",
            body: [
                "aid": String(aid),
                "multiply": "1",
                "select_like": selectLike ? "1" : "0",
                "csrf": csrf,
                "cross_domain": "true",
                "source": "web_normal",
                "ga": "1"
            ]
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
    }

    func setVideoFavorite(aid: Int, favorited: Bool) async throws {
        let csrf = try await requireCSRF()
        let folderIDs = try await favoriteFolderIDs(for: aid)
        let targetIDs: [Int]
        if favorited {
            guard let folderID = folderIDs.first else { throw BiliAPIError.missingPayload }
            targetIDs = [folderID]
        } else {
            targetIDs = folderIDs
            guard !targetIDs.isEmpty else { throw BiliAPIError.missingPayload }
        }

        let addMediaIDs = favorited ? targetIDs.map(String.init).joined(separator: ",") : ""
        let delMediaIDs = favorited ? "" : targetIDs.map(String.init).joined(separator: ",")
        let response: BiliResponse<EmptyBiliPayload> = try await postForm(
            base: baseURL,
            path: "/x/v3/fav/resource/deal",
            body: [
                "rid": String(aid),
                "type": "2",
                "add_media_ids": addMediaIDs,
                "del_media_ids": delMediaIDs,
                "csrf": csrf,
                "platform": "web",
                "gaia_source": "web_normal",
                "ga": "1"
            ]
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
    }

    func fetchFavoriteFolders(for aid: Int? = nil) async throws -> [FavoriteFolder] {
        try await favoriteFolderSummaries(rid: aid)
            .filter { $0.id > 0 }
    }

    func setVideoFavorite(aid: Int, addFolderIDs: Set<Int>, removeFolderIDs: Set<Int>) async throws {
        let csrf = try await requireCSRF()
        let addIDs = addFolderIDs
            .filter { $0 > 0 && !removeFolderIDs.contains($0) }
            .sorted()
        let removeIDs = removeFolderIDs
            .filter { $0 > 0 && !addFolderIDs.contains($0) }
            .sorted()
        guard !addIDs.isEmpty || !removeIDs.isEmpty else { return }

        let response: BiliResponse<EmptyBiliPayload> = try await postForm(
            base: baseURL,
            path: "/x/v3/fav/resource/deal",
            body: [
                "rid": String(aid),
                "type": "2",
                "add_media_ids": addIDs.map(String.init).joined(separator: ","),
                "del_media_ids": removeIDs.map(String.init).joined(separator: ","),
                "csrf": csrf,
                "platform": "web",
                "gaia_source": "web_normal",
                "ga": "1"
            ]
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
    }

    func fetchAccountHistory(page: Int = 1, pageSize: Int = 20) async throws -> [AccountVideoEntry] {
        guard await isLoggedIn() else { throw BiliAPIError.missingSESSDATA }
        let response: BiliResponse<DynamicJSONValue> = try await get(
            base: baseURL,
            path: "/x/web-interface/history/cursor",
            query: [
                "type": "archive",
                "ps": String(pageSize),
                "max": "0",
                "view_at": "0",
                "business": "archive"
            ]
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        return response.payload?.accountVideoEntries ?? []
    }

    func fetchVideoHistoryProgress(aid: Int) async throws -> VideoHistoryProgress {
        guard await isLoggedIn() else { throw BiliAPIError.missingSESSDATA }
        let response: BiliResponse<VideoHistoryProgress> = try await get(
            base: baseURL,
            path: "/x/v2/history",
            query: [
                "aid": String(aid),
                "type": "3"
            ],
            referer: "https://www.bilibili.com/video/av\(aid)"
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard let progress = response.payload else { throw BiliAPIError.missingPayload }
        return progress
    }

    func fetchAccountFavorites(page: Int = 1, pageSize: Int = 20) async throws -> [AccountVideoEntry] {
        guard await isLoggedIn() else { throw BiliAPIError.missingSESSDATA }
        let folders = try await favoriteFolderSummaries()
        var entries = [AccountVideoEntry]()
        var seen = Set<String>()
        var lastError: Error?

        for folder in folders where folder.id > 0 && entries.count < pageSize {
            do {
                let response: BiliResponse<DynamicJSONValue> = try await get(
                    base: baseURL,
                    path: "/x/v3/fav/resource/list",
                    query: [
                        "media_id": String(folder.id),
                        "pn": String(page),
                        "ps": String(pageSize),
                        "keyword": "",
                        "order": "mtime",
                        "type": "0",
                        "tid": "0",
                        "platform": "web"
                    ]
                )
                guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
                for entry in response.payload?.accountVideoEntries ?? [] where seen.insert(entry.id).inserted {
                    entries.append(entry)
                    if entries.count >= pageSize {
                        break
                    }
                }
            } catch {
                lastError = error
            }
        }

        if entries.isEmpty, let lastError {
            throw lastError
        }
        return entries
    }

    func fetchFavoriteFolderVideos(folderID: Int, page: Int = 1, pageSize: Int = 20) async throws -> [AccountVideoEntry] {
        guard await isLoggedIn() else { throw BiliAPIError.missingSESSDATA }
        let response: BiliResponse<DynamicJSONValue> = try await get(
            base: baseURL,
            path: "/x/v3/fav/resource/list",
            query: [
                "media_id": String(folderID),
                "pn": String(page),
                "ps": String(pageSize),
                "keyword": "",
                "order": "mtime",
                "type": "0",
                "tid": "0",
                "platform": "web"
            ]
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        return response.payload?.accountVideoEntries ?? []
    }

    func reportVideoHistory(aid: Int, cid: Int?, progress: TimeInterval, duration: TimeInterval?) async throws {
        let csrf = try await requireCSRF()
        var body = [
            "aid": String(aid),
            "progress": String(max(0, Int(progress))),
            "csrf": csrf,
            "gaia_source": "web_normal",
            "ga": "1"
        ]
        if let cid, cid > 0 {
            body["cid"] = String(cid)
        }
        if let duration, duration > 0 {
            body["duration"] = String(Int(duration))
        }
        let response: BiliResponse<EmptyBiliPayload> = try await postForm(
            base: baseURL,
            path: "/x/v2/history/report",
            body: body
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
    }

    func setUploaderFollowing(mid: Int, following: Bool) async throws {
        let csrf = try await requireCSRF()
        let response: BiliResponse<EmptyBiliPayload> = try await postForm(
            base: baseURL,
            path: "/x/relation/modify",
            body: [
                "fid": String(mid),
                "act": following ? "1" : "2",
                "re_src": "11",
                "csrf": csrf,
                "gaia_source": "web_normal",
                "ga": "1"
            ]
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
    }

    func fetchUploaderVideos(mid: Int, page: Int = 1) async throws -> [VideoItem] {
        let keys = try await fetchWBIKeys()
        let signed = WBISigner.sign([
            "mid": String(mid),
            "pn": String(page),
            "ps": "20",
            "tid": "0",
            "keyword": "",
            "order": "pubdate",
            "platform": "web",
            "web_location": "1550101",
            "order_avoided": "true",
            "dm_img_list": "[]",
            "dm_img_str": "V2ViR0wgMS",
            "dm_cover_img_str": "QU5HTEUgKEludGVsLCBJbnRlbChSKSBIRCBHcmFwaGljcyBEaXJlY3QzRDExIHZzXzVfMCBwc181XzApR29vZ2xlIEluYy4gKEludGVsKQ"
        ], keys: keys)

        let response: BiliResponse<UploaderVideoData> = try await get(
            base: baseURL,
            path: "/x/space/wbi/arc/search",
            query: signed,
            referer: "https://space.bilibili.com/\(mid)/video",
            responseCachePolicy: .short
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        return response.payload?.list?.vlist?
            .filter { !$0.bvid.isEmpty }
            .map { $0.asVideoItem(defaultMID: mid) } ?? []
    }

    func fetchPlayURL(
        bvid: String,
        cid: Int,
        qn: Int = 112,
        page: Int? = nil,
        preferredQuality: Int? = nil,
        supplementsQualities: Bool = true,
        preferProgressiveFastStart: Bool = false
    ) async throws -> PlayURLData {
        let snapshot = await requestSnapshot()
        let requestedQuality = preferredQuality ?? snapshot.preferredVideoQuality ?? qn
        let key = PlayURLCacheKey(
            bvid: bvid,
            cid: cid,
            requestedQuality: requestedQuality,
            audioLanguage: "default",
            fnval: "4048",
            fnver: "0",
            platform: snapshot.playbackStreamSourcePreference.cachePlatform,
            prefersProgressiveFastStart: false,
            supplementsQualities: supplementsQualities
        )
        let scope = PlayURLCacheLoginScope(
            isLoggedIn: snapshot.isLoggedIn,
            userMID: snapshot.currentUserMID,
            guestModeEnabled: snapshot.guestModeEnabled
        )
        if let cached = await playURLCache.value(for: key, scope: scope) {
            PlayerMetricsLog.logger.info(
                "playURLMemoryCacheHit bvid=\(bvid, privacy: .public) cid=\(cid, privacy: .public) qn=\(requestedQuality, privacy: .public)"
            )
            return cached
        }

        let data = try await fetchPlayURLUncached(
            bvid: bvid,
            cid: cid,
            qn: qn,
            page: page,
            preferredQuality: preferredQuality,
            supplementsQualities: supplementsQualities,
            preferProgressiveFastStart: preferProgressiveFastStart
        )
        await playURLCache.store(data, for: key, scope: scope)
        return data
    }

    func clearCachedPlayURLFailures(bvid: String) async {
        await state.clearPlayURLFailuresAndTasks(containing: bvid)
    }

    func cachedPlayablePlayURLFallback(bvid: String, cid: Int) async -> PlayURLData? {
        let snapshot = await requestSnapshot()
        let scope = PlayURLCacheLoginScope(
            isLoggedIn: snapshot.isLoggedIn,
            userMID: snapshot.currentUserMID,
            guestModeEnabled: snapshot.guestModeEnabled
        )
        return await playURLCache.playableFallback(
            bvid: bvid,
            cid: cid,
            platform: snapshot.playbackStreamSourcePreference.cachePlatform,
            scope: scope
        )
    }

    private func fetchPlayURLUncached(
        bvid: String,
        cid: Int,
        qn: Int = 112,
        page: Int? = nil,
        preferredQuality: Int? = nil,
        supplementsQualities: Bool = true,
        preferProgressiveFastStart: Bool = false
    ) async throws -> PlayURLData {
        let requestStart = CACurrentMediaTime()
        let referer = "https://www.bilibili.com/video/\(bvid)"
        let snapshot = await requestSnapshot()
        let anonymousCookieHeader = snapshot.anonymousCookieHeader
        let playCookieHeader = snapshot.cookieHeader
        let requestedQuality = preferredQuality ?? snapshot.preferredVideoQuality ?? qn
        let streamSource = snapshot.playbackStreamSourcePreference
        let query = playURLQuery(bvid: bvid, cid: cid, qn: requestedQuality, streamSource: streamSource)
        let playURLUserAgent = userAgent(for: streamSource)
        var lastError: Error?
        var bestPlayableData: PlayURLData?

        logPlayURLStage(
            "start",
            bvid: bvid,
            cid: cid,
            start: requestStart,
            data: nil,
            error: nil,
            supplementsQualities: supplementsQualities,
            preferProgressiveFastStart: false
        )

        let wbiStageStart = CACurrentMediaTime()
        do {
            let playable = try await runCachedPlayURLStage(
                "wbiPrimary",
                bvid: bvid,
                cid: cid,
                qn: requestedQuality,
                cookieMode: "auth-wbi-\(streamSource.cachePlatform)",
                start: wbiStageStart
            ) { [self] in
                let keys = try await fetchWBIKeys(priority: .userInitiated)
                return try await fetchWBIPlayURLWithCodecFallbacks(
                    bvid: bvid,
                    cid: cid,
                    requestedQuality: requestedQuality,
                    keys: keys,
                    referer: referer,
                    cookieHeader: playCookieHeader,
                    stagePrefix: "wbiPrimary",
                    cookieModePrefix: "auth-wbi-\(streamSource.cachePlatform)",
                    streamSource: streamSource,
                    priority: .userInitiated
                )
            }
            logPlayURLStage("wbiPrimary", bvid: bvid, cid: cid, start: wbiStageStart, data: playable)
            guard supplementsQualities else {
                logPlayURLStage("completeWBIPrimary", bvid: bvid, cid: cid, start: requestStart, data: playable)
                return playable
            }
            let supplemented = await supplementPlayableQualities(
                playable,
                bvid: bvid,
                cid: cid,
                referer: referer,
                cookieHeader: playCookieHeader,
                streamSource: streamSource
            )
            logPlayURLStage("wbiPrimarySupplemented", bvid: bvid, cid: cid, start: wbiStageStart, data: supplemented)
            if supplemented.highestPlayableQuality > playable.highestPlayableQuality {
                logPlayURLStage("completeWBIPrimarySupplemented", bvid: bvid, cid: cid, start: requestStart, data: supplemented)
                return supplemented
            }
            if playable.highestPlayableQuality >= 80 {
                logPlayURLStage("completeWBIPrimaryPlayable", bvid: bvid, cid: cid, start: requestStart, data: supplemented)
                return supplemented
            }
            bestPlayableData = supplemented
        } catch {
            lastError = error
        }

        let legacyStageStart = CACurrentMediaTime()
        do {
            let playable = try await runCachedPlayURLStage(
                "legacyPrimary",
                bvid: bvid,
                cid: cid,
                qn: requestedQuality,
                cookieMode: "auth-legacy-\(streamSource.cachePlatform)",
                start: legacyStageStart
            ) { [self] in
                let response: BiliResponse<PlayURLData> = try await get(
                    base: baseURL,
                    path: "/x/player/playurl",
                    query: query,
                    referer: referer,
                    userAgent: playURLUserAgent,
                    cookieHeader: playCookieHeader
                )
                return try requirePlayURLData(response, requirePlayablePayload: true)
            }
            logPlayURLStage("legacyPrimary", bvid: bvid, cid: cid, start: legacyStageStart, data: playable)
            guard supplementsQualities else {
                logPlayURLStage("completeLegacyPrimary", bvid: bvid, cid: cid, start: requestStart, data: playable)
                return playable
            }
            let supplemented = await supplementPlayableQualities(
                playable,
                bvid: bvid,
                cid: cid,
                referer: referer,
                cookieHeader: playCookieHeader,
                streamSource: streamSource
            )
            logPlayURLStage("legacyPrimarySupplemented", bvid: bvid, cid: cid, start: legacyStageStart, data: supplemented)
            if supplemented.highestPlayableQuality > (bestPlayableData?.highestPlayableQuality ?? 0) {
                bestPlayableData = supplemented
            }
            if supplemented.highestPlayableQuality >= 80 {
                logPlayURLStage("completeLegacySupplemented", bvid: bvid, cid: cid, start: requestStart, data: supplemented)
                return supplemented
            }
        } catch {
            lastError = error
        }

        let metadataStageStart = CACurrentMediaTime()
        do {
            let metadata = try await runCachedPlayURLStage(
                "anonymousMetadata",
                bvid: bvid,
                cid: cid,
                qn: requestedQuality,
                cookieMode: "anon-metadata-\(streamSource.cachePlatform)",
                start: metadataStageStart
            ) { [self] in
                try await fetchAnonymousPlayURLMetadata(
                    bvid: bvid,
                    cid: cid,
                    referer: referer,
                    query: query,
                    streamSource: streamSource
                )
            }
            logPlayURLStage("anonymousMetadata", bvid: bvid, cid: cid, start: metadataStageStart, data: metadata)
            if !metadata.playVariants.isEmpty {
                let merged = bestPlayableData?.mergingPlayableStreams(from: metadata) ?? metadata
                if merged.highestPlayableQuality >= (bestPlayableData?.highestPlayableQuality ?? 0) {
                    bestPlayableData = merged
                }
            }
        } catch {
            lastError = error
        }

        let legacyAnonymousStageStart = CACurrentMediaTime()
        do {
            let playableFallback = try await runCachedPlayURLStage(
                "legacyAnonymousFallback",
                bvid: bvid,
                cid: cid,
                qn: requestedQuality,
                cookieMode: "anon-legacy-\(streamSource.cachePlatform)",
                start: legacyAnonymousStageStart
            ) { [self] in
                let response: BiliResponse<PlayURLData> = try await get(
                    base: baseURL,
                    path: "/x/player/playurl",
                    query: query,
                    referer: referer,
                    userAgent: playURLUserAgent,
                    cookieHeader: anonymousCookieHeader
                )
                return try requirePlayURLData(response, requirePlayablePayload: true)
            }
            logPlayURLStage("legacyAnonymousFallback", bvid: bvid, cid: cid, start: legacyAnonymousStageStart, data: playableFallback)
            if let existing = bestPlayableData {
                let merged = existing.mergingPlayableStreams(from: playableFallback)
                if merged.highestPlayableQuality > existing.highestPlayableQuality
                    || playableFallback.durl?.isEmpty == false {
                    bestPlayableData = merged
                }
            } else if playableFallback.highestPlayableQuality > 0 {
                bestPlayableData = playableFallback
            }
        } catch {
            lastError = error
        }

        let webpageStageStart = CACurrentMediaTime()
        do {
            let webpagePlayable = try await runCachedPlayURLStage(
                "webpagePlayInfo",
                bvid: bvid,
                cid: cid,
                qn: requestedQuality,
                cookieMode: "auth-webpage-\(streamSource.cachePlatform)",
                start: webpageStageStart
            ) { [self] in
                try await fetchWebPagePlayInfo(
                    bvid: bvid,
                    page: page,
                    referer: referer,
                    cookieHeader: playCookieHeader
                )
            }
            logPlayURLStage("webpagePlayInfo", bvid: bvid, cid: cid, start: webpageStageStart, data: webpagePlayable)
            if let bestPlayableData {
                let merged = bestPlayableData.mergingPlayableStreams(from: webpagePlayable)
                logPlayURLStage("completeWebpageMerged", bvid: bvid, cid: cid, start: requestStart, data: merged)
                return merged
            }
            logPlayURLStage("completeWebpage", bvid: bvid, cid: cid, start: requestStart, data: webpagePlayable)
            return webpagePlayable
        } catch {
            if let bestPlayableData {
                logPlayURLStage("webpagePlayInfo", bvid: bvid, cid: cid, start: webpageStageStart, error: error)
                logPlayURLStage("completeBestFallback", bvid: bvid, cid: cid, start: requestStart, data: bestPlayableData)
                return bestPlayableData
            }
            logPlayURLStage("completeFailed", bvid: bvid, cid: cid, start: requestStart, error: lastError ?? error)
            throw lastError ?? error
        }
    }

    func fetchWebPagePlayURL(
        bvid: String,
        cid: Int,
        page: Int? = nil,
        preferredQuality: Int? = nil
    ) async throws -> PlayURLData {
        let stageStart = CACurrentMediaTime()
        let referer = "https://www.bilibili.com/video/\(bvid)"
        let snapshot = await requestSnapshot()
        let requestedQuality = preferredQuality ?? snapshot.preferredVideoQuality ?? 112
        let streamSource = snapshot.playbackStreamSourcePreference
        let data = try await runCachedPlayURLStage(
            "webpagePlayInfo",
            bvid: bvid,
            cid: cid,
            qn: requestedQuality,
            cookieMode: "auth-webpage-\(streamSource.cachePlatform)",
            start: stageStart
        ) { [self] in
            try await fetchWebPagePlayInfo(
                bvid: bvid,
                page: page,
                referer: referer,
                cookieHeader: snapshot.cookieHeader
            )
        }
        logPlayURLStage("webpagePlayInfo", bvid: bvid, cid: cid, start: stageStart, data: data)
        return data
    }

    func fetchStartupPlayURL(
        bvid: String,
        cid: Int,
        page: Int? = nil,
        preferredQuality: Int? = nil,
        startupQualityCeiling: Int? = nil
    ) async throws -> PlayURLData {
        let snapshot = await requestSnapshot()
        let environment = PlaybackEnvironment.current
        let configuredQuality = preferredQuality ?? snapshot.preferredVideoQuality
        let requestedQuality = startupRequestedQuality(
            configuredQuality: configuredQuality,
            startupQualityCeiling: startupQualityCeiling,
            environment: environment
        )
        let key = PlayURLCacheKey(
            bvid: bvid,
            cid: cid,
            requestedQuality: requestedQuality,
            audioLanguage: "default",
            fnval: "4048",
            fnver: "0",
            platform: "startup-\(snapshot.playbackStreamSourcePreference.cachePlatform)",
            prefersProgressiveFastStart: false,
            supplementsQualities: false
        )
        let scope = PlayURLCacheLoginScope(
            isLoggedIn: snapshot.isLoggedIn,
            userMID: snapshot.currentUserMID,
            guestModeEnabled: snapshot.guestModeEnabled
        )
        if let cached = await playURLCache.value(for: key, scope: scope) {
            PlayerMetricsLog.logger.info(
                "playURLStartupMemoryCacheHit bvid=\(bvid, privacy: .public) cid=\(cid, privacy: .public) qn=\(requestedQuality, privacy: .public)"
            )
            return cached
        }

        let data = try await fetchStartupPlayURLUncached(
            bvid: bvid,
            cid: cid,
            page: page,
            preferredQuality: preferredQuality,
            startupQualityCeiling: startupQualityCeiling
        )
        await playURLCache.store(data, for: key, scope: scope)
        return data
    }

    func hasCachedStartupPlayURL(
        bvid: String,
        cid: Int,
        preferredQuality: Int? = nil,
        startupQualityCeiling: Int? = nil
    ) async -> Bool {
        let snapshot = await requestSnapshot()
        let environment = PlaybackEnvironment.current
        let configuredQuality = preferredQuality ?? snapshot.preferredVideoQuality
        let requestedQuality = startupRequestedQuality(
            configuredQuality: configuredQuality,
            startupQualityCeiling: startupQualityCeiling,
            environment: environment
        )
        let key = PlayURLCacheKey(
            bvid: bvid,
            cid: cid,
            requestedQuality: requestedQuality,
            audioLanguage: "default",
            fnval: "4048",
            fnver: "0",
            platform: "startup-\(snapshot.playbackStreamSourcePreference.cachePlatform)",
            prefersProgressiveFastStart: false,
            supplementsQualities: false
        )
        let scope = PlayURLCacheLoginScope(
            isLoggedIn: snapshot.isLoggedIn,
            userMID: snapshot.currentUserMID,
            guestModeEnabled: snapshot.guestModeEnabled
        )
        return await playURLCache.contains(key, scope: scope)
    }

    private func fetchStartupPlayURLUncached(
        bvid: String,
        cid: Int,
        page: Int? = nil,
        preferredQuality: Int? = nil,
        startupQualityCeiling: Int? = nil
    ) async throws -> PlayURLData {
        let environment = PlaybackEnvironment.current
        let storedPreferredQuality = await preferredVideoQuality()
        let configuredQuality = preferredQuality ?? storedPreferredQuality
        let requestedQuality = startupRequestedQuality(
            configuredQuality: configuredQuality,
            startupQualityCeiling: startupQualityCeiling,
            environment: environment
        )
        let honorsConfiguredQuality = configuredQuality != nil && configuredQuality == requestedQuality
        let allowsUsableFallback = startupQualityCeiling != nil
        var bestStartupData: PlayURLData?
        if let racedStartupData = try await fetchRacedStartupPlayURL(
            bvid: bvid,
            cid: cid,
            page: page,
            requestedQuality: requestedQuality,
            allowsUsableFallback: allowsUsableFallback
        ) {
            if !honorsConfiguredQuality
                || racedStartupData.hasPlayableQuality(requestedQuality)
                || (allowsUsableFallback && racedStartupData.hasPlayableStreamPayload) {
                return racedStartupData
            }
            bestStartupData = preferredStartupCandidate(bestStartupData, racedStartupData)
        }

        do {
            let data = try await fetchLegacyStartupPlayURL(
                bvid: bvid,
                cid: cid,
                preferredQuality: requestedQuality
            )
            if data.hasPlayableQuality(requestedQuality) {
                return data
            }
            bestStartupData = preferredStartupCandidate(bestStartupData, data)
            logPreferredQualityMiss(
                stage: "startupLegacy",
                bvid: bvid,
                cid: cid,
                requestedQuality: requestedQuality,
                data: data
            )
        } catch {
            guard !Task.isCancelled else { throw error }
            logPlayURLStage(
                "startupLegacyFallback",
                bvid: bvid,
                cid: cid,
                start: CACurrentMediaTime(),
                error: error
            )
        }

        guard let bestStartupData else { throw BiliAPIError.emptyPlayURL }
        return bestStartupData
    }

    private nonisolated func startupRequestedQuality(
        configuredQuality: Int?,
        startupQualityCeiling: Int?,
        environment: PlaybackEnvironment
    ) -> Int {
        let requestedQuality = configuredQuality ?? LibraryStore.defaultPreferredVideoQuality
        guard let startupQualityCeiling else { return requestedQuality }
        return min(requestedQuality, startupQualityCeiling)
    }

    private func fetchRacedStartupPlayURL(
        bvid: String,
        cid: Int,
        page: Int?,
        requestedQuality: Int,
        allowsUsableFallback: Bool
    ) async throws -> PlayURLData? {
        let raceStart = CACurrentMediaTime()
        let shouldRaceWBI = await shouldAttemptStartupWBI()
        let playbackEnvironment = PlaybackEnvironment.current
        let startupGrace = playbackEnvironment.preferredPlayURLStartupGrace
        let usableStartupQuality = min(requestedQuality, playbackEnvironment.fastStartQuality)
        var bestStartupData: PlayURLData?
        var lastError: Error?

        return await withTaskGroup(of: StartupPlayURLAttempt.self, returning: PlayURLData?.self) { group in
            if startupGrace > 0 {
                group.addTask(priority: .userInitiated) {
                    try? await Task.sleep(nanoseconds: startupGrace)
                    return StartupPlayURLAttempt(stage: "startupRaceTimeout", data: nil, error: nil)
                }
            }

            group.addTask(priority: .userInitiated) { [self] in
                do {
                    let data = try await fetchWebPagePlayURL(
                        bvid: bvid,
                        cid: cid,
                        page: page,
                        preferredQuality: requestedQuality
                    )
                    return StartupPlayURLAttempt(stage: "startupWebpage", data: data, error: nil)
                } catch {
                    return StartupPlayURLAttempt(stage: "startupWebpage", data: nil, error: error)
                }
            }

            if shouldRaceWBI {
                group.addTask(priority: .userInitiated) { [self] in
                    do {
                        let keys = try await fetchWBIKeys(priority: .userInitiated)
                        let data = try await fetchWBIStartupPlayURL(
                            bvid: bvid,
                            cid: cid,
                            keys: keys,
                            preferredQuality: requestedQuality
                        )
                        return StartupPlayURLAttempt(stage: "startupWBI", data: data, error: nil)
                    } catch {
                        return StartupPlayURLAttempt(stage: "startupWBI", data: nil, error: error)
                    }
                }
            }

            while let attempt = await group.next() {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    return nil
                }

                if attempt.stage == "startupRaceTimeout" {
                    if let bestStartupData, allowsUsableFallback {
                        logPlayURLStage(
                            "startupRaceGraceFallback",
                            bvid: bvid,
                            cid: cid,
                            start: raceStart,
                            data: bestStartupData
                        )
                        group.cancelAll()
                        return bestStartupData
                    } else {
                        logPlayURLStage(
                            "startupRaceGraceExpired",
                            bvid: bvid,
                            cid: cid,
                            start: raceStart
                        )
                        continue
                    }
                }

                if let data = attempt.data {
                    bestStartupData = preferredStartupCandidate(bestStartupData, data)
                    if data.hasPlayableQuality(requestedQuality) {
                        logPlayURLStage(
                            "startupRaceWinner.\(attempt.stage)",
                            bvid: bvid,
                            cid: cid,
                            start: raceStart,
                            data: data
                        )
                        group.cancelAll()
                        return data
                    }
                    logPreferredQualityMiss(
                        stage: attempt.stage,
                        bvid: bvid,
                        cid: cid,
                        requestedQuality: requestedQuality,
                        data: data
                    )
                    if allowsUsableFallback,
                       data.highestPlayableQuality >= usableStartupQuality || data.hasPlayableStreamPayload {
                        logPlayURLStage(
                            "startupRaceUsableFallback.\(attempt.stage)",
                            bvid: bvid,
                            cid: cid,
                            start: raceStart,
                            data: data
                        )
                        group.cancelAll()
                        return data
                    }
                    continue
                }

                if let error = attempt.error {
                    lastError = error
                    logPlayURLStage(
                        "\(attempt.stage)Fallback",
                        bvid: bvid,
                        cid: cid,
                        start: raceStart,
                        error: error
                    )
                    if attempt.stage == "startupWBI" {
                        await suppressStartupWBI()
                    }
                }
            }

            if let bestStartupData {
                logPlayURLStage(
                    "startupRaceBestFallback",
                    bvid: bvid,
                    cid: cid,
                    start: raceStart,
                    data: bestStartupData
                )
            } else if let lastError {
                logPlayURLStage(
                    "startupRaceFailed",
                    bvid: bvid,
                    cid: cid,
                    start: raceStart,
                    error: lastError
                )
            }
            return bestStartupData
        }
    }

    private func cancelPlayURLStage(
        _ stage: String,
        bvid: String,
        cid: Int,
        qn: Int,
        cookieMode: String
    ) async {
        let cacheKey = playURLFailureCacheKey(
            stage: stage,
            bvid: bvid,
            cid: cid,
            qn: qn,
            cookieMode: cookieMode
        )
        await state.cancelPlayURLStage(cacheKey)
    }

    private nonisolated func userAgent(for streamSource: PlaybackStreamSourcePreference) -> String {
        switch streamSource {
        case .web:
            return Self.webUserAgent
        case .app:
            return Self.mobileUserAgent
        }
    }

    private func preferredStartupCandidate(_ lhs: PlayURLData?, _ rhs: PlayURLData) -> PlayURLData {
        guard let lhs else { return rhs }
        return rhs.highestPlayableQuality > lhs.highestPlayableQuality ? rhs : lhs
    }

    private func logPreferredQualityMiss(
        stage: String,
        bvid: String,
        cid: Int,
        requestedQuality: Int,
        data: PlayURLData
    ) {
        PlayerMetricsLog.logger.info(
            "preferredQualityMiss stage=\(stage, privacy: .public) bvid=\(bvid, privacy: .public) cid=\(cid, privacy: .public) requested=\(requestedQuality, privacy: .public) available=\(self.qualitySummary(data.playVariants), privacy: .public)"
        )
    }

    private func fetchLegacyStartupPlayURL(
        bvid: String,
        cid: Int,
        preferredQuality: Int?
    ) async throws -> PlayURLData {
        let stageStart = CACurrentMediaTime()
        let referer = "https://www.bilibili.com/video/\(bvid)"
        let snapshot = await requestSnapshot()
        let requestedQuality = preferredQuality ?? snapshot.preferredVideoQuality ?? 112
        let streamSource = snapshot.playbackStreamSourcePreference
        let query = playURLQuery(bvid: bvid, cid: cid, qn: requestedQuality, streamSource: streamSource)
        let data = try await runCachedPlayURLStage(
            "startupLegacy",
            bvid: bvid,
            cid: cid,
            qn: requestedQuality,
            cookieMode: "auth-legacy-startup-\(streamSource.cachePlatform)",
            start: stageStart
        ) { [self] in
            let response: BiliResponse<PlayURLData> = try await get(
                base: baseURL,
                path: "/x/player/playurl",
                query: query,
                referer: referer,
                userAgent: userAgent(for: streamSource),
                cookieHeader: snapshot.cookieHeader,
                priority: .userInitiated
            )
            return try requirePlayURLData(response, requirePlayablePayload: true)
        }
        logPlayURLStage("startupLegacy", bvid: bvid, cid: cid, start: stageStart, data: data)
        return data
    }

    private func fetchWBIStartupPlayURL(
        bvid: String,
        cid: Int,
        keys: WBIKeys,
        preferredQuality: Int?
    ) async throws -> PlayURLData {
        let stageStart = CACurrentMediaTime()
        let referer = "https://www.bilibili.com/video/\(bvid)"
        let snapshot = await requestSnapshot()
        let requestedQuality = preferredQuality ?? snapshot.preferredVideoQuality ?? 112
        let streamSource = snapshot.playbackStreamSourcePreference
        let authCookieHeader = snapshot.cookieHeader
        let anonymousCookieHeader = snapshot.anonymousCookieHeader
        var lastError: Error?
        do {
            let data = try await fetchWBIPlayURLWithCodecFallbacks(
                bvid: bvid,
                cid: cid,
                requestedQuality: requestedQuality,
                keys: keys,
                referer: referer,
                cookieHeader: authCookieHeader,
                stagePrefix: "startupWBI",
                cookieModePrefix: "auth-wbi-cached-\(streamSource.cachePlatform)",
                streamSource: streamSource,
                priority: .userInitiated,
                codecPreferences: PlayURLCodecPreference.primaryPlaybackOrder
            )
            logPlayURLStage("startupWBI", bvid: bvid, cid: cid, start: stageStart, data: data)
            return data
        } catch {
            lastError = error
        }

        if let error = lastError,
           shouldRetryWBIAnonymously(after: error) {
            do {
                let data = try await fetchWBIPlayURLWithCodecFallbacks(
                    bvid: bvid,
                    cid: cid,
                    requestedQuality: requestedQuality,
                    keys: keys,
                    referer: referer,
                    cookieHeader: anonymousCookieHeader,
                    stagePrefix: "startupWBIAnonymous",
                    cookieModePrefix: "anon-wbi-cached-\(streamSource.cachePlatform)",
                    streamSource: streamSource,
                    priority: .userInitiated,
                    codecPreferences: PlayURLCodecPreference.primaryPlaybackOrder
                )
                logPlayURLStage("startupWBIAnonymous", bvid: bvid, cid: cid, start: stageStart, data: data)
                return data
            } catch {
                lastError = error
            }
        }

        guard let error = lastError, shouldRefreshWBIKeys(after: error) else {
            throw lastError ?? BiliAPIError.emptyPlayURL
        }

        let refreshedKeys = try await refreshPlaybackSigningKeys()
        do {
            let data = try await fetchWBIPlayURLWithCodecFallbacks(
                bvid: bvid,
                cid: cid,
                requestedQuality: requestedQuality,
                keys: refreshedKeys,
                referer: referer,
                cookieHeader: authCookieHeader,
                stagePrefix: "startupWBIRefreshed",
                cookieModePrefix: "auth-wbi-refreshed-\(streamSource.cachePlatform)",
                streamSource: streamSource,
                priority: .userInitiated,
                codecPreferences: PlayURLCodecPreference.primaryPlaybackOrder
            )
            logPlayURLStage("startupWBIRefreshed", bvid: bvid, cid: cid, start: stageStart, data: data)
            return data
        } catch {
            lastError = error
        }

        if let error = lastError,
           shouldRetryWBIAnonymously(after: error) {
            do {
                let data = try await fetchWBIPlayURLWithCodecFallbacks(
                    bvid: bvid,
                    cid: cid,
                    requestedQuality: requestedQuality,
                    keys: refreshedKeys,
                    referer: referer,
                    cookieHeader: anonymousCookieHeader,
                    stagePrefix: "startupWBIRefreshedAnonymous",
                    cookieModePrefix: "anon-wbi-refreshed-\(streamSource.cachePlatform)",
                    streamSource: streamSource,
                    priority: .userInitiated,
                    codecPreferences: PlayURLCodecPreference.primaryPlaybackOrder
                )
                logPlayURLStage("startupWBIRefreshedAnonymous", bvid: bvid, cid: cid, start: stageStart, data: data)
                return data
            } catch {
                lastError = error
            }
        }

        if let error = lastError,
           shouldTryExtendedPlayURLCodecFallback(after: error) {
            let data = try await fetchWBIPlayURLWithCodecFallbacks(
                bvid: bvid,
                cid: cid,
                requestedQuality: requestedQuality,
                keys: refreshedKeys,
                referer: referer,
                cookieHeader: anonymousCookieHeader.isEmpty ? authCookieHeader : anonymousCookieHeader,
                stagePrefix: "startupWBIExtended",
                cookieModePrefix: "\(anonymousCookieHeader.isEmpty ? "auth-wbi-extended" : "anon-wbi-extended")-\(streamSource.cachePlatform)",
                streamSource: streamSource,
                priority: .userInitiated,
                codecPreferences: PlayURLCodecPreference.extendedPlaybackOrder
            )
            logPlayURLStage("startupWBIExtended", bvid: bvid, cid: cid, start: stageStart, data: data)
            return data
        }

        throw lastError ?? BiliAPIError.emptyPlayURL
    }

    private func shouldAttemptStartupWBI() async -> Bool {
        await state.shouldAttemptStartupWBI()
    }

    private func suppressStartupWBI(duration: CFTimeInterval = 30) async {
        await state.suppressStartupWBI(duration: duration)
    }

    private enum PlayURLCodecPreference: String, CaseIterable {
        case hevc
        case automatic
        case avc
        case av1

        static let primaryPlaybackOrder: [PlayURLCodecPreference] = [.hevc, .automatic]
        static let extendedPlaybackOrder: [PlayURLCodecPreference] = [.hevc, .automatic, .avc, .av1]

        var videoCodecid: String? {
            switch self {
            case .hevc:
                return "12"
            case .automatic:
                return nil
            case .avc:
                return "7"
            case .av1:
                return "13"
            }
        }

        var stageSuffix: String {
            switch self {
            case .hevc:
                return ""
            case .automatic:
                return "AutoCodec"
            case .avc:
                return "AVC"
            case .av1:
                return "AV1"
            }
        }
    }

    private func playURLQuery(
        bvid: String,
        cid: Int,
        qn: Int,
        streamSource: PlaybackStreamSourcePreference,
        codecPreference: PlayURLCodecPreference = .hevc
    ) -> [String: String] {
        var query = [
            "bvid": bvid,
            "cid": String(cid),
            "qn": String(qn),
            "fnval": "4048",
            "fnver": "0",
            "fourk": "1",
            "platform": streamSource.playURLPlatform,
            "high_quality": "1",
            "otype": "json",
            "try_look": "1"
        ]
        if let videoCodecid = codecPreference.videoCodecid {
            query["video_codecid"] = videoCodecid
        }
        return query
    }

    private func fetchWBIPlayURLWithCodecFallbacks(
        bvid: String,
        cid: Int,
        requestedQuality: Int,
        keys: WBIKeys,
        referer: String,
        cookieHeader: String,
        stagePrefix: String,
        cookieModePrefix: String,
        streamSource: PlaybackStreamSourcePreference,
        priority: Float,
        codecPreferences: [PlayURLCodecPreference] = PlayURLCodecPreference.extendedPlaybackOrder
    ) async throws -> PlayURLData {
        var lastError: Error?
        let orderedPreferences = codecPreferences.isEmpty ? PlayURLCodecPreference.extendedPlaybackOrder : codecPreferences
        for codecPreference in orderedPreferences {
            let stage = "\(stagePrefix)\(codecPreference.stageSuffix)"
            do {
                let stageStart = CACurrentMediaTime()
                let data = try await runCachedPlayURLStage(
                    stage,
                    bvid: bvid,
                    cid: cid,
                    qn: requestedQuality,
                    cookieMode: "\(cookieModePrefix)-\(codecPreference.rawValue)",
                    start: stageStart
                ) { [self] in
                    let query = playURLQuery(
                        bvid: bvid,
                        cid: cid,
                        qn: requestedQuality,
                        streamSource: streamSource,
                        codecPreference: codecPreference
                    )
                    let signed = WBISigner.sign(query, keys: keys)
                    let response: BiliResponse<PlayURLData> = try await get(
                        base: baseURL,
                        path: "/x/player/wbi/playurl",
                        query: signed,
                        referer: referer,
                        userAgent: userAgent(for: streamSource),
                        cookieHeader: cookieHeader,
                        priority: priority
                    )
                    return try requirePlayURLData(response, requirePlayablePayload: true)
                }
                if codecPreference != .hevc {
                    logPlayURLStage(stage, bvid: bvid, cid: cid, start: CACurrentMediaTime(), data: data)
                }
                return data
            } catch {
                guard !Task.isCancelled else { throw error }
                lastError = error
                guard shouldTryAlternatePlayURLCodec(after: error) else { break }
            }
        }
        throw lastError ?? BiliAPIError.emptyPlayURL
    }

    private func shouldTryAlternatePlayURLCodec(after error: Error) -> Bool {
        guard let biliError = error as? BiliAPIError else { return false }
        switch biliError {
        case .emptyPlayURL, .unsupportedHardwarePlayback:
            return true
        default:
            return false
        }
    }

    private func shouldRefreshWBIKeys(after error: Error) -> Bool {
        guard let biliError = error as? BiliAPIError else { return false }
        switch biliError {
        case .emptyPlayURL, .unsupportedHardwarePlayback:
            return true
        default:
            return false
        }
    }

    private func shouldRetryWBIAnonymously(after error: Error) -> Bool {
        guard let biliError = error as? BiliAPIError else { return false }
        switch biliError {
        case .emptyPlayURL, .unsupportedHardwarePlayback:
            return true
        case .api(let code, _) where code == -351:
            return true
        default:
            return false
        }
    }

    private func shouldTryExtendedPlayURLCodecFallback(after error: Error) -> Bool {
        guard let biliError = error as? BiliAPIError else { return false }
        switch biliError {
        case .unsupportedHardwarePlayback:
            return true
        default:
            return false
        }
    }

    private func runCachedPlayURLStage(
        _ stage: String,
        bvid: String,
        cid: Int,
        qn: Int,
        cookieMode: String,
        start: CFTimeInterval,
        operation: @escaping () async throws -> PlayURLData
    ) async throws -> PlayURLData {
        let cacheKey = playURLFailureCacheKey(
            stage: stage,
            bvid: bvid,
            cid: cid,
            qn: qn,
            cookieMode: cookieMode
        )
        if let cachedFailure = await state.cachedPlayURLFailure(for: cacheKey) {
            logPlayURLStage("\(stage)CachedFailure", bvid: bvid, cid: cid, start: start, error: cachedFailure)
            throw cachedFailure
        }
        if let existingTask = await state.playURLStageTask(for: cacheKey) {
            logPlayURLStage("\(stage)Joined", bvid: bvid, cid: cid, start: start)
            return try await existingTask.value
        }

        let task = Task<PlayURLData, Error>(priority: .userInitiated) {
            try await operation()
        }
        await state.setPlayURLStageTask(task, for: cacheKey)
        do {
            let data = try await task.value
            await state.clearPlayURLStageTask(for: cacheKey)
            return data
        } catch {
            await state.clearPlayURLStageTask(for: cacheKey)
            logPlayURLStage(stage, bvid: bvid, cid: cid, start: start, error: error)
            await state.storePlayURLFailure(error, for: cacheKey)
            throw error
        }
    }

    private func playURLFailureCacheKey(stage: String, bvid: String, cid: Int, qn: Int, cookieMode: String) -> String {
        "\(stage)|\(bvid)|\(cid)|\(qn)|\(cookieMode)"
    }

    nonisolated static func cacheablePlayURLFailure(_ error: Error) -> BiliAPIError? {
        guard !(error is CancellationError),
              let biliError = error as? BiliAPIError
        else { return nil }

        switch biliError {
        case .api(let code, _) where code == -351:
            return biliError
        default:
            return nil
        }
    }

    nonisolated static func playURLFailureTTL(for error: BiliAPIError) -> CFTimeInterval {
        switch error {
        case .api(let code, _) where code == -351:
            return 45
        case .emptyPlayURL:
            return 10
        default:
            return 6
        }
    }

    private func logPlayURLStage(
        _ stage: String,
        bvid: String,
        cid: Int,
        start: CFTimeInterval,
        data: PlayURLData? = nil,
        error: Error? = nil,
        supplementsQualities: Bool? = nil,
        preferProgressiveFastStart: Bool? = nil
    ) {
        let elapsed = PlayerMetricsLog.elapsedMilliseconds(since: start)
        let variants = data?.playVariants ?? []
        let playableVariants = variants.filter(\.isPlayable)
        let qualities = playableVariants
            .map { "\($0.quality)\($0.audioURL == nil ? "p" : "d")" }
            .joined(separator: ",")
        let qualitySummary = qualities.isEmpty ? "-" : qualities
        let rawSummary = data?.rawPlayURLSummary ?? "-"
        let supplementsValue = supplementsQualities.map { String($0) } ?? "-"
        let fastStartValue = preferProgressiveFastStart.map { String($0) } ?? "-"
        let errorMessage = error?.localizedDescription ?? ""

        if error != nil {
            PlayerMetricsLog.logger.error(
                "playURLStage stage=\(stage, privacy: .public) bvid=\(bvid, privacy: .public) cid=\(cid, privacy: .public) elapsedMs=\(elapsed, format: .fixed(precision: 1), privacy: .public) error=\(errorMessage, privacy: .public)"
            )
        } else {
            PlayerMetricsLog.logger.info(
                "playURLStage stage=\(stage, privacy: .public) bvid=\(bvid, privacy: .public) cid=\(cid, privacy: .public) elapsedMs=\(elapsed, format: .fixed(precision: 1), privacy: .public) variants=\(variants.count, privacy: .public) playable=\(playableVariants.count, privacy: .public) highest=\(data?.highestPlayableQuality ?? 0, privacy: .public) durl=\((data?.durl?.isEmpty == false), privacy: .public) dash=\((data?.dash?.video?.isEmpty == false), privacy: .public) qualities=\(qualitySummary, privacy: .public) raw=\(rawSummary, privacy: .public) supplements=\(supplementsValue, privacy: .public) fastStart=\(fastStartValue, privacy: .public)"
            )
        }
    }

    private func qualitySummary(_ variants: [PlayVariant]) -> String {
        let qualities = variants
            .filter(\.isPlayable)
            .map { "\($0.quality)\($0.audioURL == nil ? "p" : "d")" }
            .joined(separator: ",")
        return qualities.isEmpty ? "-" : qualities
    }

    private func supplementPlayableQualities(
        _ initialData: PlayURLData,
        bvid: String,
        cid: Int,
        referer: String,
        cookieHeader: String,
        streamSource: PlaybackStreamSourcePreference
    ) async -> PlayURLData {
        let preferredQualities = await supplementalQualityCandidates(from: initialData)
        var merged = initialData
        let supplementStart = CACurrentMediaTime()
        let keys: WBIKeys

        do {
            keys = try await fetchWBIKeys(priority: .utility)
        } catch {
            logPlayURLStage("supplementKeys", bvid: bvid, cid: cid, start: supplementStart, data: merged, error: error)
            return merged
        }

        let missingQualities = preferredQualities.filter { quality in
            !merged.playVariants.contains(where: { variant in
                variant.quality == quality
                    && variant.isPlayable
                    && !variant.isProgressiveFastStart
                    && !Self.playVariantNeedsFrameRateSupplement(variant)
            })
        }

        for batchStart in stride(from: 0, to: missingQualities.count, by: 2) {
            let batchEnd = min(batchStart + 2, missingQualities.count)
            let batch = Array(missingQualities[batchStart..<batchEnd])
            let results = await fetchSupplementalQualityBatch(
                batch,
                bvid: bvid,
                cid: cid,
                keys: keys,
                referer: referer,
                cookieHeader: cookieHeader,
                streamSource: streamSource
            )
            for result in results {
                guard let data = result.data else { continue }
                merged = merged.mergingPlayableStreams(from: data)
            }
        }

        logPlayURLStage("supplementComplete", bvid: bvid, cid: cid, start: supplementStart, data: merged)
        return merged
    }

    private nonisolated static func playVariantNeedsFrameRateSupplement(_ variant: PlayVariant) -> Bool {
        guard [116, 74].contains(variant.quality) else { return false }
        if let frameRate = DASHStream.numericFrameRate(from: variant.frameRate) {
            return frameRate < 50
        }
        return true
    }

    private func fetchSupplementalQualityBatch(
        _ qualities: [Int],
        bvid: String,
        cid: Int,
        keys: WBIKeys,
        referer: String,
        cookieHeader: String,
        streamSource: PlaybackStreamSourcePreference
    ) async -> [SupplementalPlayURLResult] {
        switch qualities.count {
        case 0:
            return []
        case 1:
            return [
                await fetchSupplementalQuality(
                    qualities[0],
                    bvid: bvid,
                    cid: cid,
                    keys: keys,
                    referer: referer,
                    cookieHeader: cookieHeader,
                    streamSource: streamSource
                )
            ]
        case 2:
            async let first = fetchSupplementalQuality(qualities[0], bvid: bvid, cid: cid, keys: keys, referer: referer, cookieHeader: cookieHeader, streamSource: streamSource)
            async let second = fetchSupplementalQuality(qualities[1], bvid: bvid, cid: cid, keys: keys, referer: referer, cookieHeader: cookieHeader, streamSource: streamSource)
            return await [first, second]
        case 3:
            async let first = fetchSupplementalQuality(qualities[0], bvid: bvid, cid: cid, keys: keys, referer: referer, cookieHeader: cookieHeader, streamSource: streamSource)
            async let second = fetchSupplementalQuality(qualities[1], bvid: bvid, cid: cid, keys: keys, referer: referer, cookieHeader: cookieHeader, streamSource: streamSource)
            async let third = fetchSupplementalQuality(qualities[2], bvid: bvid, cid: cid, keys: keys, referer: referer, cookieHeader: cookieHeader, streamSource: streamSource)
            return await [first, second, third]
        default:
            async let first = fetchSupplementalQuality(qualities[0], bvid: bvid, cid: cid, keys: keys, referer: referer, cookieHeader: cookieHeader, streamSource: streamSource)
            async let second = fetchSupplementalQuality(qualities[1], bvid: bvid, cid: cid, keys: keys, referer: referer, cookieHeader: cookieHeader, streamSource: streamSource)
            async let third = fetchSupplementalQuality(qualities[2], bvid: bvid, cid: cid, keys: keys, referer: referer, cookieHeader: cookieHeader, streamSource: streamSource)
            async let fourth = fetchSupplementalQuality(qualities[3], bvid: bvid, cid: cid, keys: keys, referer: referer, cookieHeader: cookieHeader, streamSource: streamSource)
            return await [first, second, third, fourth]
        }
    }

    private func fetchSupplementalQuality(
        _ quality: Int,
        bvid: String,
        cid: Int,
        keys: WBIKeys,
        referer: String,
        cookieHeader: String,
        streamSource: PlaybackStreamSourcePreference
    ) async -> SupplementalPlayURLResult {
        let qualityStart = CACurrentMediaTime()
        do {
            let data = try await runCachedPlayURLStage(
                "supplementQ\(quality)",
                bvid: bvid,
                cid: cid,
                qn: quality,
                cookieMode: "auth-wbi-\(streamSource.cachePlatform)",
                start: qualityStart
            ) { [self] in
                let query = playURLQuery(bvid: bvid, cid: cid, qn: quality, streamSource: streamSource)
                let signed = WBISigner.sign(query, keys: keys)
                let response: BiliResponse<PlayURLData> = try await get(
                    base: baseURL,
                    path: "/x/player/wbi/playurl",
                    query: signed,
                    referer: referer,
                    userAgent: userAgent(for: streamSource),
                    cookieHeader: cookieHeader,
                    priority: .utility
                )
                return try requirePlayURLData(response, requirePlayablePayload: true)
            }
            logPlayURLStage("supplementQ\(quality)", bvid: bvid, cid: cid, start: qualityStart, data: data)
            return SupplementalPlayURLResult(quality: quality, data: data)
        } catch {
            return SupplementalPlayURLResult(quality: quality, data: nil)
        }
    }

    private func supplementalQualityCandidates(from data: PlayURLData) async -> [Int] {
        var qualities = [Int]()

        func append(_ quality: Int?) {
            guard let quality, quality > 0, !qualities.contains(quality) else { return }
            qualities.append(quality)
        }

        data.acceptQuality?.forEach(append)
        data.supportFormats?.forEach { append($0.quality) }
        data.dash?.video?.forEach { append($0.id) }
        append(await preferredVideoQuality())
        Self.supplementalQualityLadder.forEach(append)
        return qualities
    }

    private func fetchWebPagePlayInfo(bvid: String, page: Int?, referer: String, cookieHeader: String?) async throws -> PlayURLData {
        guard var components = URLComponents(string: "https://www.bilibili.com/video/\(bvid)/") else {
            throw BiliAPIError.invalidURL
        }
        if let page, page > 1 {
            components.queryItems = [URLQueryItem(name: "p", value: String(page))]
        }
        guard let url = components.url else { throw BiliAPIError.invalidURL }

        var request = URLRequest(url: url)
        let resolvedCookieHeader: String
        if let cookieHeader {
            resolvedCookieHeader = cookieHeader
        } else {
            resolvedCookieHeader = await self.cookieHeader()
        }
        applyCommonHeaders(
            to: &request,
            referer: referer,
            userAgent: Self.webUserAgent,
            cookieHeader: resolvedCookieHeader
        )
        let (data, _) = try await data(for: request, priority: .userInitiated)
        guard !data.isEmpty else { throw BiliAPIError.emptyData }
        guard let html = String(data: data, encoding: .utf8),
              let json = Self.extractWebPagePlayInfoJSON(from: html)
        else {
            throw BiliAPIError.missingPayload
        }

        let response: BiliResponse<PlayURLData> = try await Self.decode(Data(json.utf8), priority: .userInitiated)
        return try requirePlayURLData(response, requirePlayablePayload: true)
    }

    private func mergeDisplayFormatsIfAvailable(
        _ playableData: PlayURLData,
        bvid: String,
        cid: Int,
        referer: String,
        query: [String: String]
    ) async -> PlayURLData {
        let streamSource = await playbackStreamSourcePreference()
        guard let metadata = try? await fetchAnonymousPlayURLMetadata(
            bvid: bvid,
            cid: cid,
            referer: referer,
            query: query,
            streamSource: streamSource
        ) else {
            return playableData
        }
        return playableData.mergingDisplayFormats(from: metadata)
    }

    private func fetchAnonymousPlayURLMetadata(
        bvid: String,
        cid: Int,
        referer: String,
        query: [String: String],
        streamSource: PlaybackStreamSourcePreference
    ) async throws -> PlayURLData {
        let response: BiliResponse<PlayURLData> = try await get(
            base: baseURL,
            path: "/x/player/playurl",
            query: query,
            referer: referer,
            userAgent: userAgent(for: streamSource),
            cookieHeader: await anonymousCookieHeader()
        )
        return try requirePlayURLData(response)
    }

    private static func extractWebPagePlayInfoJSON(from html: String) -> String? {
        let markers = [
            "window.__playinfo__=",
            "window.__playinfo__ =",
            "__playinfo__="
        ]
        for marker in markers {
            guard let markerRange = html.range(of: marker),
                  let json = extractBalancedJSONObject(from: html[markerRange.upperBound...])
            else { continue }
            return json
        }
        return nil
    }

    private static func extractBalancedJSONObject(from source: Substring) -> String? {
        guard let start = source.firstIndex(of: "{") else { return nil }
        var index = start
        var depth = 0
        var isInsideString = false
        var isEscaped = false

        while index < source.endIndex {
            let character = source[index]
            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
            } else {
                if character == "\"" {
                    isInsideString = true
                } else if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1
                    if depth == 0 {
                        return String(source[start...index])
                    }
                }
            }
            index = source.index(after: index)
        }
        return nil
    }

    func searchVideos(keyword: String, page: Int = 1, order: String? = nil) async throws -> [VideoItem] {
        let results: [SearchVideoItem] = try await searchTypedResults(
            keyword: keyword,
            searchType: "video",
            page: page,
            order: order
        )
        return results
            .filter { !$0.bvid.isEmpty }
            .map { $0.asVideoItem() }
    }

    func searchUsers(keyword: String, page: Int = 1) async throws -> [SearchUserItem] {
        try await searchTypedResults(keyword: keyword, searchType: "bili_user", page: page)
            .filter { $0.mid > 0 }
    }

    func searchBangumi(keyword: String, page: Int = 1) async throws -> [SearchMediaItem] {
        try await searchTypedResults(keyword: keyword, searchType: "media_bangumi", page: page)
    }

    func searchMovies(keyword: String, page: Int = 1) async throws -> [SearchMediaItem] {
        try await searchTypedResults(keyword: keyword, searchType: "media_ft", page: page)
    }

    func searchArticles(keyword: String, page: Int = 1) async throws -> [SearchArticleItem] {
        try await searchTypedResults(keyword: keyword, searchType: "article", page: page)
            .filter { $0.articleID > 0 }
    }

    private func searchTypedResults<Result: Decodable>(
        keyword: String,
        searchType: String,
        page: Int = 1,
        order: String? = nil
    ) async throws -> [Result] {
        let keys = try await fetchWBIKeys(priority: .userInitiated)
        var params = [
            "keyword": keyword,
            "search_type": searchType,
            "page": String(page),
            "page_size": "20"
        ]
        if let order, !order.isEmpty {
            params["order"] = order
        }
        let signed = WBISigner.sign(params, keys: keys)
        let response: BiliResponse<SearchTypeData<Result>> = try await get(
            base: baseURL,
            path: "/x/web-interface/wbi/search/type",
            query: signed,
            responseCachePolicy: .brief
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        return response.payload?.result ?? []
    }

    func fetchSearchSuggest(term: String) async throws -> [SearchSuggestItem] {
        let response: BiliResponse<SearchSuggestResponse> = try await get(
            base: baseURL,
            path: "/x/web-interface/search/suggest",
            query: ["term": term, "main_ver": "v1", "highlight": ""],
            responseCachePolicy: .brief
        )
        return response.payload?.tag ?? []
    }

    func fetchHotSearch() async throws -> [HotSearchItem] {
        let response: BiliResponse<HotSearchData> = try await get(
            base: baseURL,
            path: "/x/web-interface/wbi/search/square",
            query: ["limit": "10"],
            responseCachePolicy: .short
        )
        return response.payload?.trending?.list ?? []
    }

    func fetchDynamicFeed(offset: String? = nil) async throws -> DynamicFeedData {
        var query = [
            "type": "all",
            "platform": "web",
            "features": "itemOpusStyle,listOnlyfans,opusBigCover,onlyfansVote,decorationCard,onlyfansAssetsV2,forwardListHidden,ugcDelete",
            "web_location": "333.1365"
        ]
        if let offset, !offset.isEmpty {
            query["offset"] = offset
        }
        let response: BiliResponse<DynamicFeedData> = try await get(
            base: baseURL,
            path: "/x/polymer/web-dynamic/v1/feed/all",
            query: query,
            responseCachePolicy: .brief
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard let data = response.payload else { throw BiliAPIError.missingPayload }
        return data
    }

    func generateQRCodeLogin() async throws -> QRCodeLoginInfo {
        let response: BiliResponse<QRCodeLoginInfo> = try await get(
            base: passportURL,
            path: "/x/passport-login/web/qrcode/generate",
            query: [:],
            referer: "https://passport.bilibili.com/login",
            userAgent: Self.webUserAgent
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard let info = response.payload else { throw BiliAPIError.missingPayload }
        return info
    }

    func pollQRCodeLogin(qrcodeKey: String) async throws -> QRCodeLoginPollResult {
        let request = try await makeRequest(
            base: passportURL,
            path: "/x/passport-login/web/qrcode/poll",
            query: ["qrcode_key": qrcodeKey],
            referer: "https://passport.bilibili.com/login",
            userAgent: Self.webUserAgent
        )
        let (data, response) = try await data(for: request, priority: .utility)
        guard !data.isEmpty else { throw BiliAPIError.emptyData }

        let apiResponse: BiliResponse<QRCodeLoginPollData> = try await Self.decode(data, priority: .utility)
        guard apiResponse.code == 0 else {
            throw BiliAPIError.api(code: apiResponse.code, message: apiResponse.displayMessage)
        }
        guard let pollData = apiResponse.payload else { throw BiliAPIError.missingPayload }
        return QRCodeLoginPollResult(
            data: pollData,
            cookies: Self.biliCookies(from: response, requestURL: request.url)
        )
    }

    func fetchComments(aid: Int, cursor: String = "", sort: CommentSort = .hot) async throws -> CommentPage {
        try await fetchComments(oid: String(aid), type: 1, cursor: cursor, sort: sort)
    }

    func fetchComments(oid: String, type: Int, cursor: String = "", sort: CommentSort = .hot) async throws -> CommentPage {
        let mode = sort == .hot ? "3" : "2"
        let pagination = try Self.commentPaginationString(offset: cursor)
        let response: BiliResponse<CommentPage> = try await get(
            base: baseURL,
            path: "/x/v2/reply/main",
            query: [
                "oid": oid,
                "type": String(type),
                "mode": mode,
                "plat": "1",
                "pagination_str": pagination
            ],
            priority: URLSessionTask.defaultPriority
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        return response.payload ?? CommentPage(replies: [], topReplies: [], cursor: nil)
    }

    private static func commentPaginationString(offset: String) throws -> String {
        let data = try JSONEncoder().encode(CommentPaginationRequest(offset: offset))
        return String(decoding: data, as: UTF8.self)
    }

    func fetchCommentReplies(aid: Int, root: Int, page: Int = 1) async throws -> CommentPage {
        try await fetchCommentReplies(oid: String(aid), type: 1, root: root, page: page)
    }

    func fetchCommentReplies(oid: String, type: Int, root: Int, page: Int = 1) async throws -> CommentPage {
        let response: BiliResponse<CommentPage> = try await get(
            base: baseURL,
            path: "/x/v2/reply/reply",
            query: [
                "oid": oid,
                "type": String(type),
                "root": String(root),
                "pn": String(page),
                "ps": "20"
            ],
            priority: .background
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        return response.payload ?? CommentPage(replies: [], topReplies: [], cursor: nil)
    }

    func fetchCommentDialog(aid: Int, root: Int, dialog: Int, size: Int = 20) async throws -> CommentPage {
        try await fetchCommentDialog(oid: String(aid), type: 1, root: root, dialog: dialog, size: size)
    }

    func fetchCommentDialog(oid: String, type: Int, root: Int, dialog: Int, size: Int = 20) async throws -> CommentPage {
        let response: BiliResponse<CommentPage> = try await get(
            base: baseURL,
            path: "/x/v2/reply/dialog/cursor",
            query: [
                "oid": oid,
                "type": String(type),
                "root": String(root),
                "dialog": String(dialog),
                "size": String(size)
            ],
            priority: .background
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        return response.payload ?? CommentPage(replies: [], topReplies: [], cursor: nil)
    }

    func fetchNavUser() async throws -> NavUserInfo {
        if let task = await state.navUserTask() {
            return try await task.value
        }
        let task = Task<NavUserInfo, Error>(priority: .utility) { [self] in
            let response: BiliResponse<NavUserInfo> = try await get(
                base: baseURL,
                path: "/x/web-interface/nav",
                query: [:]
            )
            guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
            guard let info = response.payload else { throw BiliAPIError.missingPayload }
            return info
        }
        await state.setNavUserTask(task)
        do {
            let info = try await task.value
            await state.clearNavUserTask()
            return info
        } catch {
            await state.clearNavUserTask()
            throw error
        }
    }

    func fetchLiveRooms(page: Int = 1, refreshIndex: Int = 0) async throws -> [LiveRoom] {
        var query = [
            "platform": "web",
            "page": String(page),
            "page_size": "20"
        ]
        if refreshIndex > 0 {
            query["fresh_idx"] = String(refreshIndex)
            query["fresh_type"] = "3"
            query["_"] = String(Int(Date().timeIntervalSince1970 * 1000))
        }

        let request = try await makeRequest(
            base: liveURL,
            path: "/xlive/web-interface/v1/webMain/getMoreRecList",
            query: query,
            referer: "https://live.bilibili.com",
            cookieHeader: await anonymousCookieHeader(),
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        let (data, _) = try await data(for: request, priority: .background)
        guard !data.isEmpty else { throw BiliAPIError.emptyData }

        do {
            let response: BiliResponse<LiveRecommendData> = try await Self.decode(data, priority: .background)
            guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
            if let rooms = response.payload?.recommendRoomList, !rooms.isEmpty {
                return rooms.filter { $0.roomID > 0 }
            }
        } catch {
            let rooms = try Self.decodeLiveRoomsFallback(from: data)
            if !rooms.isEmpty {
                return rooms
            }
            throw error
        }

        return try Self.decodeLiveRoomsFallback(from: data)
    }

    func fetchLiveAreas() async throws -> [LiveAreaGroup] {
        let response: BiliResponse<[LiveAreaGroup]> = try await get(
            base: liveURL,
            path: "/room/v1/Area/getList",
            query: ["show_pinyin": "1"],
            referer: "https://live.bilibili.com",
            responseCachePolicy: .long
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        return (response.payload ?? []).filter { $0.id > 0 }
    }

    func fetchLiveRooms(parentAreaID: Int, areaID: Int = 0, page: Int = 1) async throws -> [LiveRoom] {
        let response: BiliResponse<[LiveRoom]> = try await get(
            base: liveURL,
            path: "/room/v1/area/getRoomList",
            query: [
                "parent_area_id": String(parentAreaID),
                "area_id": String(areaID),
                "page": String(page),
                "page_size": "20",
                "sort_type": "online",
                "platform": "web"
            ],
            referer: "https://live.bilibili.com",
            responseCachePolicy: .brief
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        return (response.payload ?? []).filter { $0.roomID > 0 }
    }

    func fetchLiveRoomInfo(roomID: Int) async throws -> LiveRoomInfo {
        let response: BiliResponse<LiveRoomInfo> = try await get(
            base: liveURL,
            path: "/room/v1/Room/get_info",
            query: ["room_id": String(roomID)],
            referer: "https://live.bilibili.com/\(roomID)",
            responseCachePolicy: .short
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard let info = response.payload else { throw BiliAPIError.missingPayload }
        return info
    }

    func fetchLiveAnchorInfo(roomID: Int) async throws -> LiveAnchorInfoData {
        let response: BiliResponse<LiveAnchorInfoData> = try await get(
            base: liveURL,
            path: "/live_user/v1/UserInfo/get_anchor_in_room",
            query: ["roomid": String(roomID)],
            referer: "https://live.bilibili.com/\(roomID)",
            responseCachePolicy: .short
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard let info = response.payload else { throw BiliAPIError.missingPayload }
        return info
    }

    func fetchLiveRoomSummary(uid: Int) async throws -> LiveRoomSummary {
        let response: BiliResponse<LiveRoomSummary> = try await get(
            base: liveURL,
            path: "/room/v1/Room/getRoomInfoOld",
            query: ["mid": String(uid)],
            referer: "https://space.bilibili.com/\(uid)",
            responseCachePolicy: .short
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard let info = response.payload, info.roomID > 0 else { throw BiliAPIError.missingPayload }
        return info
    }

    func fetchLiveStreamURL(roomID: Int) async throws -> URL {
        guard let url = try await fetchLiveStreamInfo(roomID: roomID).candidates.first?.url else {
            throw BiliAPIError.missingPayload
        }
        return url
    }

    func fetchLiveStreamCandidates(roomID: Int) async throws -> [LiveStreamURLCandidate] {
        try await fetchLiveStreamInfo(roomID: roomID).candidates
    }

    func fetchLiveStreamInfo(roomID: Int, quality: Int? = nil) async throws -> LiveStreamFetchResult {
        var lastError: Error?
        let requestedQuality = quality ?? 10000
        let attempts: [(stageName: String, query: [String: String])] = [
            ("web", [
                "room_id": String(roomID),
                "protocol": "0,1",
                "format": "0,1,2",
                "codec": "0,1",
                "qn": String(requestedQuality),
                "platform": "web"
            ]),
            ("android", [
                "room_id": String(roomID),
                "protocol": "0,1",
                "format": "0,1,2",
                "codec": "0",
                "qn": String(requestedQuality),
                "platform": "android"
            ])
        ]

        let racedAttempt = await withTaskGroup(
            of: Result<LiveStreamAttemptOutcome, Error>.self,
            returning: (result: LiveStreamFetchResult?, error: Error?, qualities: [LiveStreamQuality]).self
        ) { group in
            for attempt in attempts {
                group.addTask { [self] in
                    do {
                        return .success(
                            try await fetchLiveStreamInfoAttempt(
                                roomID: roomID,
                                query: attempt.query,
                                stageName: attempt.stageName
                            )
                        )
                    } catch {
                        return .failure(error)
                    }
                }
            }

            var collectedQualities: [LiveStreamQuality] = []
            var lastAttemptError: Error?
            while let attemptResult = await group.next() {
                switch attemptResult {
                case .success(let outcome):
                    collectedQualities.append(contentsOf: outcome.qualities)
                    guard !outcome.candidates.isEmpty else {
                        lastAttemptError = BiliAPIError.missingPayload
                        continue
                    }
                    group.cancelAll()
                    PlayerMetricsLog.logger.info(
                        "liveStreamInfoReady room=\(roomID, privacy: .public) stage=\(outcome.stageName, privacy: .public) candidates=\(outcome.candidates.count, privacy: .public) qualities=\(outcome.qualities.count, privacy: .public) elapsedMs=\(outcome.elapsedMilliseconds, format: .fixed(precision: 1), privacy: .public)"
                    )
                    return (
                        LiveStreamFetchResult(
                            candidates: Self.removingDuplicateLiveURLs(from: outcome.candidates),
                            qualities: LiveStreamQuality.merged(collectedQualities)
                        ),
                        nil,
                        collectedQualities
                    )
                case .failure(let error):
                    lastAttemptError = error
                }
            }
            return (nil, lastAttemptError, collectedQualities)
        }

        if let result = racedAttempt.result {
            return result
        }
        lastError = racedAttempt.error

        do {
            let legacyStart = CACurrentMediaTime()
            let legacyCandidates = try await fetchLegacyLiveStreamCandidates(roomID: roomID)
            if !legacyCandidates.isEmpty {
                PlayerMetricsLog.logger.info(
                    "liveStreamInfoLegacyReady room=\(roomID, privacy: .public) candidates=\(legacyCandidates.count, privacy: .public) elapsedMs=\(PlayerMetricsLog.elapsedMilliseconds(since: legacyStart), format: .fixed(precision: 1), privacy: .public)"
                )
                return LiveStreamFetchResult(
                    candidates: legacyCandidates,
                    qualities: LiveStreamQuality.merged(racedAttempt.qualities)
                )
            }
        } catch {
            lastError = error
        }

        throw lastError ?? BiliAPIError.missingPayload
    }

    private func fetchLiveStreamInfoAttempt(
        roomID: Int,
        query: [String: String],
        stageName: String
    ) async throws -> LiveStreamAttemptOutcome {
        let attemptStart = CACurrentMediaTime()
        let response: BiliResponse<LivePlayInfoData> = try await get(
            base: liveURL,
            path: "/xlive/web-room/v2/index/getRoomPlayInfo",
            query: query,
            referer: "https://live.bilibili.com/\(roomID)",
            userAgent: Self.webUserAgent,
            cachePolicy: .reloadIgnoringLocalCacheData,
            priority: .userInitiated,
            timeoutInterval: 6
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        return LiveStreamAttemptOutcome(
            stageName: stageName,
            candidates: response.payload?.playableURLCandidates ?? [],
            qualities: response.payload?.availableQualities ?? [],
            elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: attemptStart)
        )
    }

    func fetchLiveDanmakuConnectionInfo(
        roomID: Int,
        cookieHeader: String? = nil
    ) async throws -> LiveDanmakuConnectionInfoData {
        let query = [
            "id": String(roomID),
            "type": "0"
        ]
        let signedQuery: [String: String]
        do {
            let keys = try await fetchWBIKeys(priority: .utility)
            signedQuery = WBISigner.sign(query, keys: keys)
        } catch {
            signedQuery = query
        }
        var request = try await makeRequest(
            base: liveURL,
            path: "/xlive/web-room/v1/index/getDanmuInfo",
            query: signedQuery,
            referer: "https://live.bilibili.com/\(roomID)",
            userAgent: Self.webUserAgent,
            cookieHeader: cookieHeader,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        request.setValue("https://live.bilibili.com", forHTTPHeaderField: "Origin")
        request.networkServiceType = .default
        request.timeoutInterval = 6
        let (data, _) = try await data(for: request, priority: .utility)
        guard !data.isEmpty else { throw BiliAPIError.emptyData }
        let response: BiliResponse<LiveDanmakuConnectionInfoData> = try await Self.decode(data, priority: .utility)
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        guard let info = response.payload else {
            throw BiliAPIError.missingPayload
        }
        return info
    }

    func liveDanmakuClientContext(roomID: Int) async -> LiveDanmakuClientContext {
        let snapshot = await requestSnapshot()
        let baseCookieHeader = snapshot.cookieHeader.isEmpty ? snapshot.anonymousCookieHeader : snapshot.cookieHeader
        let fallbackBuvid = Self.cookieValue(named: "buvid3", in: baseCookieHeader)
            ?? Self.cookieValue(named: "buvid3", in: snapshot.anonymousCookieHeader)
            ?? ""
        let buvid = await liveDanmakuBuvid3(fallback: fallbackBuvid)
        let cookieHeader = Self.cookieHeader(baseCookieHeader, settingCookieNamed: "buvid3", to: buvid)
        return LiveDanmakuClientContext(
            uid: snapshot.currentUserMID ?? 0,
            buvid: buvid,
            cookieHeader: cookieHeader,
            headers: [
                "User-Agent": Self.webUserAgent,
                "Referer": "https://live.bilibili.com/\(roomID)",
                "Origin": "https://live.bilibili.com",
                "Accept-Language": "zh-CN,zh;q=0.9",
                "Cookie": cookieHeader
            ]
        )
    }

    private func liveDanmakuBuvid3(fallback: String) async -> String {
        guard let buvid = try? await fetchFrontendFingerprintBuvid3(), !buvid.isEmpty else {
            return fallback
        }
        await saveResolvedBuvid3(buvid)
        return buvid
    }

    private func fetchFrontendFingerprintBuvid3() async throws -> String {
        let response: BiliResponse<FrontendFingerprintData> = try await get(
            base: baseURL,
            path: "/x/frontend/finger/spi",
            query: [:],
            referer: "https://www.bilibili.com",
            userAgent: Self.webUserAgent,
            cachePolicy: .reloadIgnoringLocalCacheData,
            priority: .utility,
            timeoutInterval: 4
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        guard let buvid = response.payload?.buvid3?.trimmingCharacters(in: .whitespacesAndNewlines),
              !buvid.isEmpty
        else {
            throw BiliAPIError.missingPayload
        }
        return buvid
    }

    @MainActor
    private func saveResolvedBuvid3(_ value: String) {
        sessionStore.saveBuvid3(value)
    }

    private static func removingDuplicateLiveURLs(from candidates: [LiveStreamURLCandidate]) -> [LiveStreamURLCandidate] {
        var seen = Set<String>()
        var result: [LiveStreamURLCandidate] = []
        for candidate in candidates {
            guard seen.insert(candidate.url.absoluteString).inserted else { continue }
            result.append(candidate)
        }
        return result
    }

    private func fetchLegacyLiveStreamURL(roomID: Int) async throws -> URL {
        guard let url = try await fetchLegacyLiveStreamCandidates(roomID: roomID).first?.url else {
            throw BiliAPIError.missingPayload
        }
        return url
    }

    private func fetchLegacyLiveStreamCandidates(roomID: Int) async throws -> [LiveStreamURLCandidate] {
        let response: BiliResponse<LiveRoomPlayURLData> = try await get(
            base: liveURL,
            path: "/room/v1/Room/playUrl",
            query: [
                "cid": String(roomID),
                "quality": "4",
                "platform": "h5"
            ],
            referer: "https://live.bilibili.com/\(roomID)",
            userAgent: Self.mobileUserAgent,
            cachePolicy: .reloadIgnoringLocalCacheData,
            priority: .userInitiated,
            timeoutInterval: 6
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        let candidates = response.payload?.playableURLCandidates ?? []
        guard !candidates.isEmpty else {
            throw BiliAPIError.missingPayload
        }
        return candidates
    }

    func fetchFollowedLiveRooms(page: Int = 1, pageSize: Int = 10) async throws -> [LiveRoom] {
        let response: BiliResponse<FollowedLiveRoomsData> = try await get(
            base: liveURL,
            path: "/xlive/web-ucenter/v1/xfetter/FeedList",
            query: [
                "page": String(page),
                "page_size": String(pageSize),
                "platform": "web"
            ],
            referer: "https://live.bilibili.com",
            responseCachePolicy: .brief
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        return response.payload?.roomList.filter { $0.roomID > 0 && $0.isLive } ?? []
    }

    private func fetchWBIKeys(priority: Float = URLSessionTask.defaultPriority) async throws -> WBIKeys {
        if let keys = await freshCachedWBIKeys() {
            return keys
        }

        if let task = await state.wbiKeysFetchTask() {
            return try await task.value
        }

        let task = Task<WBIKeys, Error>(priority: priority >= URLSessionTask.highPriority ? .userInitiated : .utility) { [self] in
            let response: BiliResponse<NavUserInfo> = try await get(
                base: baseURL,
                path: "/x/web-interface/nav",
                query: [:],
                priority: priority
            )
            guard let image = response.payload?.wbiImg else {
                if response.code != 0 {
                    throw BiliAPIError.api(code: response.code, message: response.displayMessage)
                }
                throw BiliAPIError.missingPayload
            }
            return WBIKeys(
                imgKey: Self.fileStem(from: image.imgURL),
                subKey: Self.fileStem(from: image.subURL)
            )
        }
        await state.setWBIKeysFetchTask(task)
        do {
            let keys = try await task.value
            await state.storeWBIKeys(keys)
            return keys
        } catch {
            await state.clearWBIKeysFetchTask()
            throw error
        }
    }

    private func freshCachedWBIKeys() async -> WBIKeys? {
        await state.freshCachedWBIKeys()
    }

    private func get<T: Decodable>(
        base: URL,
        path: String,
        query: [String: String],
        referer: String = "https://www.bilibili.com",
        userAgent: String? = nil,
        cookieHeader: String? = nil,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy,
        responseCachePolicy: BiliAPIResponseCachePolicy? = nil,
        priority: Float = URLSessionTask.defaultPriority,
        timeoutInterval: TimeInterval? = nil
    ) async throws -> T {
        var request = try await makeRequest(
            base: base,
            path: path,
            query: query,
            referer: referer,
            userAgent: userAgent,
            cookieHeader: cookieHeader,
            cachePolicy: cachePolicy
        )
        request.networkServiceType = priority >= URLSessionTask.highPriority ? .responsiveData : .default
        if let timeoutInterval {
            request.timeoutInterval = timeoutInterval
        }
        let responseCacheKey = responseCachePolicy.flatMap { _ in Self.responseCacheKey(for: request) }
        if responseCachePolicy != nil,
           let responseCacheKey,
           let cachedData = await BiliAPIResponseMemoryCache.shared.freshData(for: responseCacheKey) {
            guard !cachedData.isEmpty else { throw BiliAPIError.emptyData }
            return try await Self.decode(cachedData, priority: priority)
        }

        if let responseCachePolicy,
           responseCachePolicy.staleTTL > responseCachePolicy.freshTTL,
           cachePolicy != .reloadIgnoringLocalCacheData,
           let responseCacheKey,
           let staleData = await BiliAPIResponseMemoryCache.shared.staleData(for: responseCacheKey),
           let decoded: T = try? await Self.decode(staleData, priority: priority) {
            refreshResponseCacheInBackground(
                request,
                cacheKey: responseCacheKey,
                policy: responseCachePolicy,
                priority: priority
            )
            return decoded
        }

        do {
            let (data, _) = try await data(for: request, priority: priority)
            guard !data.isEmpty else { throw BiliAPIError.emptyData }
            let decoded: T = try await Self.decode(data, priority: priority)
            if let responseCachePolicy, let responseCacheKey {
                await BiliAPIResponseMemoryCache.shared.store(
                    data,
                    for: responseCacheKey,
                    policy: responseCachePolicy
                )
            }
            return decoded
        } catch {
            if let responseCachePolicy,
               responseCachePolicy.staleTTL > responseCachePolicy.freshTTL,
               let responseCacheKey,
               let staleData = await BiliAPIResponseMemoryCache.shared.staleData(for: responseCacheKey),
               let decoded: T = try? await Self.decode(staleData, priority: priority) {
                return decoded
            }
            throw error
        }
    }

    private func refreshResponseCacheInBackground(
        _ request: URLRequest,
        cacheKey: String,
        policy: BiliAPIResponseCachePolicy,
        priority: Float
    ) {
        Task(priority: priority >= URLSessionTask.highPriority ? .userInitiated : .utility) { [self] in
            do {
                let (data, _) = try await data(for: request, priority: priority)
                guard !data.isEmpty else { return }
                await BiliAPIResponseMemoryCache.shared.store(data, for: cacheKey, policy: policy)
            } catch {
                return
            }
        }
    }

    private func postForm<T: Decodable>(
        base: URL,
        path: String,
        body: [String: String],
        referer: String = "https://www.bilibili.com",
        userAgent: String? = nil
    ) async throws -> T {
        var request = try await makeRequest(base: base, path: path, query: [:], referer: referer, userAgent: userAgent)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(from: body)
        let (data, _) = try await data(for: request, priority: .userInitiated)
        guard !data.isEmpty else { throw BiliAPIError.emptyData }
        return try await Self.decode(data, priority: .userInitiated)
    }

    private func makeRequest(
        base: URL,
        path: String,
        query: [String: String],
        referer: String = "https://www.bilibili.com",
        userAgent: String? = nil,
        cookieHeader: String? = nil,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
    ) async throws -> URLRequest {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw BiliAPIError.invalidURL
        }
        components.path = path
        if !query.isEmpty {
            components.queryItems = query
                .sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw BiliAPIError.invalidURL }
        var request = URLRequest(url: url, cachePolicy: cachePolicy)
        let resolvedCookieHeader: String
        if let cookieHeader {
            resolvedCookieHeader = cookieHeader
        } else {
            resolvedCookieHeader = await self.cookieHeader()
        }
        applyCommonHeaders(to: &request, referer: referer, userAgent: userAgent, cookieHeader: resolvedCookieHeader)
        if cachePolicy != .useProtocolCachePolicy {
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        }
        return request
    }

    private func data(for request: URLRequest, priority: Float = URLSessionTask.defaultPriority) async throws -> (Data, URLResponse) {
        var request = request
        request.networkServiceType = priority >= URLSessionTask.highPriority ? .responsiveData : .default
        let response = try await BiliNetworkRetry.data(
            session: session,
            request: request,
            priority: priority,
            policy: .api
        )
        ResourceCacheAutoTrim.schedule()
        return response
    }

    private nonisolated static func responseCacheKey(for request: URLRequest) -> String? {
        guard let url = request.url else { return nil }
        let userAgent = request.value(forHTTPHeaderField: "User-Agent") ?? ""
        let referer = request.value(forHTTPHeaderField: "Referer") ?? ""
        let cookieScope = responseCacheCookieScope(request.value(forHTTPHeaderField: "Cookie") ?? "")
        return [
            url.absoluteString,
            "ua:\(userAgent)",
            "ref:\(referer)",
            "cookie:\(cookieScope)"
        ].joined(separator: "\n")
    }

    private nonisolated static func responseCacheCookieScope(_ cookieHeader: String) -> String {
        let mid = cookieValue(named: "DedeUserID", in: cookieHeader) ?? "0"
        let hasSession = cookieValue(named: "SESSDATA", in: cookieHeader) != nil
        let buvid = cookieValue(named: "buvid3", in: cookieHeader) ?? "-"
        return "\(hasSession ? "auth" : "anon")|mid:\(mid)|buvid:\(buvid)"
    }

    private func requireCSRF() async throws -> String {
        let snapshot = await requestSnapshot()
        guard snapshot.isLoggedIn else {
            throw BiliAPIError.missingSESSDATA
        }
        guard let csrf = snapshot.csrfToken, !csrf.isEmpty else {
            throw BiliAPIError.missingCSRF
        }
        return csrf
    }

    private func applyCommonHeaders(to request: inout URLRequest, referer: String, userAgent: String? = nil, cookieHeader: String) {
        BiliURLSessionFactory.apiHeaders(
            referer: referer,
            userAgent: userAgent ?? Self.mobileUserAgent,
            cookieHeader: cookieHeader
        )
        .forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
    }

    private func guestModeCookieHeader() async -> String? {
        let snapshot = await requestSnapshot()
        return snapshot.guestModeEnabled ? snapshot.anonymousCookieHeader : nil
    }

    private nonisolated static func cookieValue(named name: String, in header: String) -> String? {
        header
            .split(separator: ";")
            .compactMap { item -> String? in
                let pair = item.split(separator: "=", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                guard pair.count == 2, pair[0] == name, !pair[1].isEmpty else { return nil }
                return pair[1]
            }
            .first
    }

    private static func cookieHeader(
        _ header: String,
        settingCookieNamed name: String,
        to value: String
    ) -> String {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        var didReplace = false
        var items = header
            .split(separator: ";")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { item -> String in
                let pair = item.split(separator: "=", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                guard pair.count == 2, pair[0] == name else { return item }
                didReplace = true
                return "\(name)=\(trimmedValue)"
            }
        if !didReplace, !trimmedValue.isEmpty {
            items.insert("\(name)=\(trimmedValue)", at: 0)
        }
        return items.joined(separator: "; ")
    }

    private static func formBody(from fields: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    private nonisolated static func decode<T: Decodable>(
        _ type: T.Type = T.self,
        from data: Data,
        priority: Float
    ) async throws -> T {
        let taskPriority: TaskPriority
        if priority >= URLSessionTask.highPriority {
            taskPriority = .userInitiated
        } else if priority <= URLSessionTask.lowPriority {
            taskPriority = .background
        } else {
            taskPriority = .utility
        }

        return try await Task.detached(priority: taskPriority) {
            try JSONDecoder.bili.decode(T.self, from: data)
        }.value
    }

    private nonisolated static func decode<T: Decodable>(
        _ data: Data,
        priority: Float
    ) async throws -> T {
        try await decode(T.self, from: data, priority: priority)
    }

    private func favoriteFolderIDs(for aid: Int) async throws -> [Int] {
        try await favoriteFolderSummaries(rid: aid)
            .filter { $0.id > 0 }
            .map(\.id)
    }

    private func favoriteFolderSummaries(rid: Int? = nil) async throws -> [FavoriteFolder] {
        let userMID = try await currentUserMID()
        var query = [
            "up_mid": String(userMID),
            "type": "2"
        ]
        if let rid {
            query["rid"] = String(rid)
        }
        let response: BiliResponse<FavoriteFolderListData> = try await get(
            base: baseURL,
            path: "/x/v3/fav/folder/created/list-all",
            query: query
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        return response.payload?.list ?? []
    }

    private func currentUserMID() async throws -> Int {
        if let mid = await requestSnapshot().currentUserMID, mid > 0 {
            return mid
        }
        let user = try await fetchNavUser()
        guard let mid = user.mid, mid > 0 else { throw BiliAPIError.missingPayload }
        return mid
    }

    private func requirePlayURLData(_ response: BiliResponse<PlayURLData>, requirePlayablePayload: Bool = false) throws -> PlayURLData {
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        guard let data = response.payload else { throw BiliAPIError.missingPayload }
        if let code = data.code, code != 0 {
            throw BiliAPIError.api(code: code, message: data.message)
        }
        if requirePlayablePayload, data.playVariants.isEmpty {
            if data.hasAnyPlayURLPayload {
                throw BiliAPIError.unsupportedHardwarePlayback(
                    "播放接口已返回地址，但没有可用的 HEVC/AAC 硬解组合（\(data.rawPlayURLSummary)）"
                )
            }
            throw BiliAPIError.emptyPlayURL
        }
        return data
    }

    private static func fileStem(from url: String) -> String {
        let filename = URL(string: url)?.deletingPathExtension().lastPathComponent
        return filename ?? ""
    }

    private static func decodeLiveRoomsFallback(from data: Data) throws -> [LiveRoom] {
        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dataObject = object["data"] as? [String: Any]
        else {
            return []
        }

        let candidates = ["recommend_room_list", "room_list", "list"]
        for key in candidates {
            guard let rawRooms = dataObject[key] as? [[String: Any]], !rawRooms.isEmpty else {
                continue
            }
            return rawRooms.compactMap { rawRoom in
                guard JSONSerialization.isValidJSONObject(rawRoom),
                      let roomData = try? JSONSerialization.data(withJSONObject: rawRoom),
                      let room = try? JSONDecoder.bili.decode(LiveRoom.self, from: roomData),
                      room.roomID > 0
                else {
                    return nil
                }
                return room
            }
        }

        return []
    }

    private static func biliCookies(from response: URLResponse, requestURL: URL?) -> [HTTPCookie] {
        var cookies = [HTTPCookie]()

        if let httpResponse = response as? HTTPURLResponse,
           let requestURL {
            let headers = httpResponse.allHeaderFields.reduce(into: [String: String]()) { result, field in
                let key = (field.key.base as? String) ?? String(describing: field.key)
                result[key] = String(describing: field.value)
            }
            cookies.append(contentsOf: HTTPCookie.cookies(withResponseHeaderFields: headers, for: requestURL))
        }

        if cookies.isEmpty {
            let storageURLs = [
                requestURL,
                URL(string: "https://passport.bilibili.com"),
                URL(string: "https://www.bilibili.com"),
                URL(string: "https://api.bilibili.com")
            ].compactMap { $0 }
            cookies.append(contentsOf: storageURLs.flatMap { HTTPCookieStorage.shared.cookies(for: $0) ?? [] })
        }

        var seen = Set<String>()
        return cookies.filter { cookie in
            guard cookie.domain.localizedCaseInsensitiveContains("bilibili.com") else { return false }
            let key = "\(cookie.name)|\(cookie.domain)|\(cookie.path)"
            return seen.insert(key).inserted
        }
    }
}

nonisolated enum CommentSort: CaseIterable, Identifiable, Hashable {
    case hot
    case time

    var id: Self { self }

    var title: String {
        switch self {
        case .hot:
            return "最热"
        case .time:
            return "最新"
        }
    }
}

extension JSONDecoder {
    nonisolated static var bili: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        return decoder
    }
}

private extension Float {
    static var userInitiated: Float { URLSessionTask.highPriority }
    static var utility: Float { URLSessionTask.defaultPriority }
    static var background: Float { URLSessionTask.lowPriority }
}

private struct SupplementalPlayURLResult {
    let quality: Int
    let data: PlayURLData?
}

nonisolated private struct CommentPaginationRequest: Encodable {
    let offset: String
}

private struct StartupPlayURLAttempt: Sendable {
    let stage: String
    let data: PlayURLData?
    let error: Error?
}

private struct CachedPlayURLFailure {
    let error: BiliAPIError
    let expiresAt: CFTimeInterval
}

private struct CachedDanmaku {
    let items: [DanmakuItem]
    let storedAt: CFTimeInterval
}

nonisolated private struct LiveStreamAttemptOutcome {
    let stageName: String
    let candidates: [LiveStreamURLCandidate]
    let qualities: [LiveStreamQuality]
    let elapsedMilliseconds: Double
}

nonisolated private struct FrontendFingerprintData: Decodable {
    let buvid3: String?

    enum CodingKeys: String, CodingKey {
        case buvid3 = "b_3"
    }
}

private actor BiliAPIClientState {
    private struct PersistedWBIKeys: Codable {
        let keys: WBIKeys
        let storedAt: Date
    }

    private static let persistedWBIKeysKey = "cc.bili.persisted-wbi-keys.v1"
    private let playURLFailureCacheLimit = 96
    private let danmakuCacheLimit = 12
    private let danmakuCacheTTL: CFTimeInterval = 30 * 60
    private var cachedWBIKeys: WBIKeys?
    private var cachedWBIKeysDate: Date?
    private var wbiKeysTask: Task<WBIKeys, Error>?
    private var navTask: Task<NavUserInfo, Error>?
    private var videoListTasks: [String: Task<[VideoItem], Error>] = [:]
    private var videoDetailTasks: [String: Task<VideoItem, Error>] = [:]
    private var uploaderProfileTasks: [Int: Task<UploaderProfile, Error>] = [:]
    private var appRecommendFeedIndex: Int?
    private var startupWBISuppressedUntil: CFTimeInterval = 0
    private var playURLFailureCache: [String: CachedPlayURLFailure] = [:]
    private var playURLStageTasks: [String: Task<PlayURLData, Error>] = [:]
    private var danmakuCache: [Int: CachedDanmaku] = [:]

    func freshCachedWBIKeys() -> WBIKeys? {
        guard let keys = cachedWBIKeys,
              let date = cachedWBIKeysDate,
              Date().timeIntervalSince(date) < 12 * 60 * 60
        else {
            if let persisted = persistedWBIKeys() {
                cachedWBIKeys = persisted.keys
                cachedWBIKeysDate = persisted.storedAt
                return persisted.keys
            }
            return nil
        }
        return keys
    }

    func storeWBIKeys(_ keys: WBIKeys) {
        cachedWBIKeys = keys
        cachedWBIKeysDate = Date()
        wbiKeysTask = nil
        persistWBIKeys(keys)
    }

    func clearWBIKeys() {
        cachedWBIKeys = nil
        cachedWBIKeysDate = nil
        wbiKeysTask = nil
        UserDefaults.standard.removeObject(forKey: Self.persistedWBIKeysKey)
    }

    private func persistedWBIKeys() -> PersistedWBIKeys? {
        guard let data = UserDefaults.standard.data(forKey: Self.persistedWBIKeysKey),
              let persisted = try? JSONDecoder().decode(PersistedWBIKeys.self, from: data),
              Date().timeIntervalSince(persisted.storedAt) < 12 * 60 * 60
        else { return nil }
        return persisted
    }

    private func persistWBIKeys(_ keys: WBIKeys) {
        let persisted = PersistedWBIKeys(keys: keys, storedAt: Date())
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        UserDefaults.standard.set(data, forKey: Self.persistedWBIKeysKey)
    }

    func wbiKeysFetchTask() -> Task<WBIKeys, Error>? {
        wbiKeysTask
    }

    func setWBIKeysFetchTask(_ task: Task<WBIKeys, Error>) {
        wbiKeysTask = task
    }

    func clearWBIKeysFetchTask() {
        wbiKeysTask = nil
    }

    func navUserTask() -> Task<NavUserInfo, Error>? {
        navTask
    }

    func setNavUserTask(_ task: Task<NavUserInfo, Error>) {
        navTask = task
    }

    func clearNavUserTask() {
        navTask = nil
    }

    func videoListTask(for key: String) -> Task<[VideoItem], Error>? {
        videoListTasks[key]
    }

    func setVideoListTask(_ task: Task<[VideoItem], Error>, for key: String) {
        videoListTasks[key] = task
    }

    func clearVideoListTask(for key: String) {
        videoListTasks[key] = nil
    }

    func appRecommendFeedIndex(defaulting defaultIndex: Int) -> Int {
        appRecommendFeedIndex ?? defaultIndex
    }

    func setAppRecommendFeedIndex(_ index: Int?) {
        guard let index, index > 0 else { return }
        appRecommendFeedIndex = index
    }

    func videoDetailTask(for bvid: String) -> Task<VideoItem, Error>? {
        videoDetailTasks[bvid]
    }

    func setVideoDetailTask(_ task: Task<VideoItem, Error>, for bvid: String) {
        videoDetailTasks[bvid] = task
    }

    func clearVideoDetailTask(for bvid: String) {
        videoDetailTasks[bvid] = nil
    }

    func uploaderProfileTask(for mid: Int) -> Task<UploaderProfile, Error>? {
        uploaderProfileTasks[mid]
    }

    func setUploaderProfileTask(_ task: Task<UploaderProfile, Error>, for mid: Int) {
        uploaderProfileTasks[mid] = task
    }

    func clearUploaderProfileTask(for mid: Int) {
        uploaderProfileTasks[mid] = nil
    }

    func shouldAttemptStartupWBI() -> Bool {
        CACurrentMediaTime() >= startupWBISuppressedUntil
    }

    func suppressStartupWBI(duration: CFTimeInterval) {
        startupWBISuppressedUntil = CACurrentMediaTime() + duration
    }

    func playURLStageTask(for key: String) -> Task<PlayURLData, Error>? {
        playURLStageTasks[key]
    }

    func setPlayURLStageTask(_ task: Task<PlayURLData, Error>, for key: String) {
        playURLStageTasks[key] = task
    }

    func clearPlayURLStageTask(for key: String) {
        playURLStageTasks[key] = nil
    }

    func clearPlayURLFailuresAndTasks(containing bvid: String) {
        guard !bvid.isEmpty else { return }
        let failureKeys = playURLFailureCache.keys.filter { $0.contains("|\(bvid)|") }
        failureKeys.forEach { playURLFailureCache[$0] = nil }
        let taskKeys = playURLStageTasks.keys.filter { $0.contains("|\(bvid)|") }
        for key in taskKeys {
            playURLStageTasks[key]?.cancel()
            playURLStageTasks[key] = nil
        }
    }

    func cachedDanmaku(for cid: Int) -> [DanmakuItem]? {
        let now = CACurrentMediaTime()
        guard let cached = danmakuCache[cid] else { return nil }
        guard now - cached.storedAt < danmakuCacheTTL else {
            danmakuCache[cid] = nil
            return nil
        }
        return cached.items
    }

    func storeDanmaku(_ items: [DanmakuItem], for cid: Int) {
        danmakuCache[cid] = CachedDanmaku(items: items, storedAt: CACurrentMediaTime())
        trimDanmakuCacheIfNeeded()
    }

    func cancelPlayURLStage(_ key: String) {
        playURLStageTasks[key]?.cancel()
        playURLStageTasks[key] = nil
    }

    func cachedPlayURLFailure(for key: String) -> BiliAPIError? {
        let now = CACurrentMediaTime()
        if let cached = playURLFailureCache[key] {
            if cached.expiresAt > now {
                return cached.error
            }
            playURLFailureCache[key] = nil
        }
        trimExpiredPlayURLFailures(now: now)
        return nil
    }

    func storePlayURLFailure(_ error: Error, for key: String) {
        guard let cacheableError = BiliAPIClient.cacheablePlayURLFailure(error) else { return }
        let now = CACurrentMediaTime()
        playURLFailureCache[key] = CachedPlayURLFailure(
            error: cacheableError,
            expiresAt: now + BiliAPIClient.playURLFailureTTL(for: cacheableError)
        )
        trimPlayURLFailureCacheIfNeeded(now: now)
    }

    private func trimExpiredPlayURLFailures(now: CFTimeInterval = CACurrentMediaTime()) {
        playURLFailureCache = playURLFailureCache.filter { $0.value.expiresAt > now }
    }

    private func trimPlayURLFailureCacheIfNeeded(now: CFTimeInterval = CACurrentMediaTime()) {
        trimExpiredPlayURLFailures(now: now)
        guard playURLFailureCache.count > playURLFailureCacheLimit else { return }
        let overflow = playURLFailureCache.count - playURLFailureCacheLimit
        let expiredKeys = playURLFailureCache
            .sorted { $0.value.expiresAt < $1.value.expiresAt }
            .prefix(overflow)
            .map(\.key)
        expiredKeys.forEach { playURLFailureCache[$0] = nil }
    }

    private func trimDanmakuCacheIfNeeded(now: CFTimeInterval = CACurrentMediaTime()) {
        danmakuCache = danmakuCache.filter { now - $0.value.storedAt < danmakuCacheTTL }
        guard danmakuCache.count > danmakuCacheLimit else { return }
        let overflow = danmakuCache.count - danmakuCacheLimit
        let oldestKeys = danmakuCache
            .sorted { $0.value.storedAt < $1.value.storedAt }
            .prefix(overflow)
            .map(\.key)
        oldestKeys.forEach { danmakuCache[$0] = nil }
    }
}
