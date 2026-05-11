import Foundation

@MainActor
final class BiliAPIClient {
    private let baseURL = URL(string: "https://api.bilibili.com")!
    private let passportURL = URL(string: "https://passport.bilibili.com")!
    private let liveURL = URL(string: "https://api.live.bilibili.com")!
    private let commentURL = URL(string: "https://comment.bilibili.com")!
    private static let mobileUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    private static let webUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    private let session: URLSession
    private let sessionStore: SessionStore
    private let libraryStore: LibraryStore

    private var cachedWBIKeys: WBIKeys?
    private var cachedWBIKeysDate: Date?

    init(session: URLSession = .shared, sessionStore: SessionStore, libraryStore: LibraryStore) {
        self.session = session
        self.sessionStore = sessionStore
        self.libraryStore = libraryStore
    }

    func fetchRecommendFeed(freshIndex: Int = 0) async throws -> [VideoItem] {
        let keys = try await fetchWBIKeys()
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
            cookieHeader: guestModeCookieHeader,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        return response.payload?.item?.compactMap { $0.asVideoItem() } ?? []
    }

    func fetchPopularVideos(page: Int = 1) async throws -> [VideoItem] {
        let response: BiliResponse<BiliPage<VideoItem>> = try await get(
            base: baseURL,
            path: "/x/web-interface/popular",
            query: [
                "pn": String(page),
                "ps": "20"
            ]
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        return response.payload?.list ?? []
    }

    func fetchVideoDetail(bvid: String) async throws -> VideoItem {
        let response: BiliResponse<VideoItem> = try await get(
            base: baseURL,
            path: "/x/web-interface/view",
            query: ["bvid": bvid]
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard let item = response.payload else { throw BiliAPIError.missingPayload }
        return item
    }

    func fetchVideoRelated(bvid: String) async throws -> [VideoItem] {
        let response: BiliResponse<[VideoItem]> = try await get(
            base: baseURL,
            path: "/x/web-interface/archive/related",
            query: ["bvid": bvid]
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        return response.payload ?? []
    }

    func fetchUploaderProfile(mid: Int) async throws -> UploaderProfile {
        let response: BiliResponse<UploaderProfile> = try await get(
            base: baseURL,
            path: "/x/web-interface/card",
            query: ["mid": String(mid)]
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard let profile = response.payload else { throw BiliAPIError.missingPayload }
        return profile
    }

    func fetchVideoInteractionState(aid: Int) async throws -> VideoInteractionState {
        guard sessionStore.isLoggedIn else {
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
        let csrf = try requireCSRF()
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
        let csrf = try requireCSRF()
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
        let csrf = try requireCSRF()
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

    func fetchAccountHistory(page: Int = 1, pageSize: Int = 20) async throws -> [AccountVideoEntry] {
        guard sessionStore.isLoggedIn else { throw BiliAPIError.missingSESSDATA }
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

    func fetchAccountFavorites(page: Int = 1, pageSize: Int = 20) async throws -> [AccountVideoEntry] {
        guard sessionStore.isLoggedIn else { throw BiliAPIError.missingSESSDATA }
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

    func reportVideoHistory(aid: Int, cid: Int?, progress: TimeInterval, duration: TimeInterval?) async throws {
        let csrf = try requireCSRF()
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
        let csrf = try requireCSRF()
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
            referer: "https://space.bilibili.com/\(mid)/video"
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        return response.payload?.list?.vlist?
            .filter { !$0.bvid.isEmpty }
            .map { $0.asVideoItem(defaultMID: mid) } ?? []
    }

    func fetchPlayURL(bvid: String, cid: Int, qn: Int = 112, page: Int? = nil) async throws -> PlayURLData {
        let referer = "https://www.bilibili.com/video/\(bvid)"
        let anonymousCookieHeader = sessionStore.anonymousCookieHeader()
        let playCookieHeader = sessionStore.cookieHeader()
        let query = playURLQuery(bvid: bvid, cid: cid, qn: qn)
        let html5Query = [
            "bvid": bvid,
            "cid": String(cid),
            "qn": "64",
            "fnval": "0",
            "fnver": "0",
            "platform": "html5"
        ]
        var lastError: Error?
        var bestPlayableData: PlayURLData?

        do {
            let keys = try await fetchWBIKeys()
            let signed = WBISigner.sign(query, keys: keys)
            let response: BiliResponse<PlayURLData> = try await get(
            base: baseURL,
            path: "/x/player/wbi/playurl",
            query: signed,
            referer: referer,
            userAgent: Self.webUserAgent,
            cookieHeader: playCookieHeader,
            priority: .userInitiated
        )
            let playable = try requirePlayURLData(response, requirePlayablePayload: true)
            let supplemented = await supplementPlayableQualities(
                playable,
                bvid: bvid,
                cid: cid,
                referer: referer,
                cookieHeader: playCookieHeader
            )
            if supplemented.highestPlayableQuality > playable.highestPlayableQuality {
                return supplemented
            }
            if playable.highestPlayableQuality >= 80 {
                return supplemented
            }
            bestPlayableData = supplemented
        } catch {
            lastError = error
        }

        do {
            let response: BiliResponse<PlayURLData> = try await get(
                base: baseURL,
                path: "/x/player/playurl",
                query: query,
                referer: referer,
                userAgent: Self.webUserAgent,
                cookieHeader: playCookieHeader
            )
            let playable = try requirePlayURLData(response, requirePlayablePayload: true)
            let supplemented = await supplementPlayableQualities(
                playable,
                bvid: bvid,
                cid: cid,
                referer: referer,
                cookieHeader: playCookieHeader
            )
            if supplemented.highestPlayableQuality > (bestPlayableData?.highestPlayableQuality ?? 0) {
                bestPlayableData = supplemented
            }
            if supplemented.highestPlayableQuality >= 80 {
                return supplemented
            }
        } catch {
            lastError = error
        }

        do {
            let response: BiliResponse<PlayURLData> = try await get(
                base: baseURL,
                path: "/x/player/playurl",
                query: html5Query,
                referer: referer,
                userAgent: Self.mobileUserAgent,
                cookieHeader: playCookieHeader
            )
            let playableFallback = try requirePlayURLData(response, requirePlayablePayload: true)
            if playableFallback.highestPlayableQuality > (bestPlayableData?.highestPlayableQuality ?? 0) {
                bestPlayableData = playableFallback
            }
        } catch {
            lastError = error
        }

        do {
            let metadata = try await fetchAnonymousPlayURLMetadata(
                bvid: bvid,
                cid: cid,
                referer: referer,
                query: query
            )
            if !metadata.playVariants.isEmpty {
                let merged = bestPlayableData?.mergingPlayableStreams(from: metadata) ?? metadata
                if merged.highestPlayableQuality > (bestPlayableData?.highestPlayableQuality ?? 0) {
                    bestPlayableData = merged
                }
            }
        } catch {
            lastError = error
        }

        do {
            let response: BiliResponse<PlayURLData> = try await get(
                base: baseURL,
                path: "/x/player/playurl",
                query: html5Query,
                referer: referer,
                userAgent: Self.mobileUserAgent,
                cookieHeader: anonymousCookieHeader
            )
            let playableFallback = try requirePlayURLData(response, requirePlayablePayload: true)
            if playableFallback.highestPlayableQuality > (bestPlayableData?.highestPlayableQuality ?? 0) {
                bestPlayableData = playableFallback
            }
        } catch {
            lastError = error
        }

        do {
            let response: BiliResponse<PlayURLData> = try await get(
                base: baseURL,
                path: "/x/player/playurl",
                query: query,
                referer: referer,
                userAgent: Self.webUserAgent,
                cookieHeader: anonymousCookieHeader
            )
            let playableFallback = try requirePlayURLData(response, requirePlayablePayload: true)
            if playableFallback.highestPlayableQuality > (bestPlayableData?.highestPlayableQuality ?? 0) {
                bestPlayableData = playableFallback
            }
        } catch {
            lastError = error
        }

        do {
            let webpagePlayable = try await fetchWebPagePlayInfo(
                bvid: bvid,
                page: page,
                referer: referer,
                cookieHeader: playCookieHeader
            )
            if let bestPlayableData {
                return bestPlayableData.mergingPlayableStreams(from: webpagePlayable)
            }
            return webpagePlayable
        } catch {
            if let bestPlayableData {
                return bestPlayableData
            }
            throw lastError ?? error
        }
    }

    private func playURLQuery(bvid: String, cid: Int, qn: Int) -> [String: String] {
        [
            "bvid": bvid,
            "cid": String(cid),
            "qn": String(qn),
            "fnval": "4048",
            "fnver": "0",
            "fourk": "1",
            "platform": "pc",
            "high_quality": "1"
        ]
    }

    private func supplementPlayableQualities(
        _ initialData: PlayURLData,
        bvid: String,
        cid: Int,
        referer: String,
        cookieHeader: String
    ) async -> PlayURLData {
        let preferredQualities = [116, 112, 80, 74, 64, 32]
        var merged = initialData

        for quality in preferredQualities where !merged.playVariants.contains(where: { $0.quality == quality && $0.isPlayable }) {
            do {
                let query = playURLQuery(bvid: bvid, cid: cid, qn: quality)
                let keys = try await fetchWBIKeys()
                let signed = WBISigner.sign(query, keys: keys)
                let response: BiliResponse<PlayURLData> = try await get(
                    base: baseURL,
                    path: "/x/player/wbi/playurl",
                    query: signed,
                referer: referer,
                userAgent: Self.webUserAgent,
                cookieHeader: cookieHeader,
                priority: .userInitiated
            )
                let data = try requirePlayURLData(response, requirePlayablePayload: true)
                merged = merged.mergingPlayableStreams(from: data)
            } catch {
                continue
            }
        }

        return merged
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
        applyCommonHeaders(to: &request, referer: referer, userAgent: Self.webUserAgent, cookieHeader: cookieHeader)
        let (data, _) = try await data(for: request, priority: .userInitiated)
        guard !data.isEmpty else { throw BiliAPIError.emptyData }
        guard let html = String(data: data, encoding: .utf8),
              let json = Self.extractWebPagePlayInfoJSON(from: html)
        else {
            throw BiliAPIError.missingPayload
        }

        let response = try JSONDecoder.bili.decode(BiliResponse<PlayURLData>.self, from: Data(json.utf8))
        return try requirePlayURLData(response, requirePlayablePayload: true)
    }

    private func mergeDisplayFormatsIfAvailable(
        _ playableData: PlayURLData,
        bvid: String,
        cid: Int,
        referer: String,
        query: [String: String]
    ) async -> PlayURLData {
        guard let metadata = try? await fetchAnonymousPlayURLMetadata(bvid: bvid, cid: cid, referer: referer, query: query) else {
            return playableData
        }
        return playableData.mergingDisplayFormats(from: metadata)
    }

    private func fetchAnonymousPlayURLMetadata(bvid: String, cid: Int, referer: String, query: [String: String]) async throws -> PlayURLData {
        let response: BiliResponse<PlayURLData> = try await get(
            base: baseURL,
            path: "/x/player/playurl",
            query: query,
            referer: referer,
            userAgent: Self.webUserAgent,
            cookieHeader: sessionStore.anonymousCookieHeader()
        )
        return try requirePlayURLData(response)
    }

    private static func extractWebPagePlayInfoJSON(from html: String) -> String? {
        guard let marker = html.range(of: "window.__playinfo__=") else { return nil }
        let afterMarker = html[marker.upperBound...]
        guard let end = afterMarker.range(of: "</script>") else { return nil }
        let json = afterMarker[..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return json.isEmpty ? nil : String(json)
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
        let keys = try await fetchWBIKeys()
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
            query: signed
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        return response.payload?.result ?? []
    }

    func fetchSearchSuggest(term: String) async throws -> [SearchSuggestItem] {
        let response: BiliResponse<SearchSuggestResponse> = try await get(
            base: baseURL,
            path: "/x/web-interface/search/suggest",
            query: ["term": term, "main_ver": "v1", "highlight": ""]
        )
        return response.payload?.tag ?? []
    }

    func fetchHotSearch() async throws -> [HotSearchItem] {
        let response: BiliResponse<HotSearchData> = try await get(
            base: baseURL,
            path: "/x/web-interface/wbi/search/square",
            query: ["limit": "10"]
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
            query: query
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
        let request = try makeRequest(
            base: passportURL,
            path: "/x/passport-login/web/qrcode/poll",
            query: ["qrcode_key": qrcodeKey],
            referer: "https://passport.bilibili.com/login",
            userAgent: Self.webUserAgent
        )
        let (data, response) = try await data(for: request, priority: .utility)
        guard !data.isEmpty else { throw BiliAPIError.emptyData }

        let apiResponse = try JSONDecoder.bili.decode(BiliResponse<QRCodeLoginPollData>.self, from: data)
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
        let pagination = #"{"offset":"\#(cursor)"}"#
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
            priority: .background
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        return response.payload ?? CommentPage(replies: [], topReplies: [], cursor: nil)
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

    func fetchDanmakuXML(cid: Int) async throws -> String {
        let url = commentURL.appendingPathComponent("\(cid).xml")
        var request = URLRequest(url: url)
        applyCommonHeaders(to: &request, referer: "https://www.bilibili.com")
        let (data, _) = try await data(for: request, priority: .userInitiated)
        guard !data.isEmpty else { throw BiliAPIError.emptyData }
        return String(data: data, encoding: .utf8) ?? ""
    }

    func fetchNavUser() async throws -> NavUserInfo {
        let response: BiliResponse<NavUserInfo> = try await get(
            base: baseURL,
            path: "/x/web-interface/nav",
            query: [:]
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard let info = response.payload else { throw BiliAPIError.missingPayload }
        return info
    }

    func fetchLiveRooms(page: Int = 1) async throws -> [LiveRoom] {
        let request = try makeRequest(
            base: liveURL,
            path: "/xlive/web-interface/v1/webMain/getMoreRecList",
            query: [
                "platform": "web",
                "page": String(page),
                "page_size": "20"
            ],
            referer: "https://live.bilibili.com"
        )
        let (data, _) = try await data(for: request, priority: .background)
        guard !data.isEmpty else { throw BiliAPIError.emptyData }

        do {
            let response = try JSONDecoder.bili.decode(BiliResponse<LiveRecommendData>.self, from: data)
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
            referer: "https://live.bilibili.com"
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
            referer: "https://live.bilibili.com"
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        return (response.payload ?? []).filter { $0.roomID > 0 }
    }

    func fetchLiveRoomInfo(roomID: Int) async throws -> LiveRoomInfo {
        let response: BiliResponse<LiveRoomInfo> = try await get(
            base: liveURL,
            path: "/room/v1/Room/get_info",
            query: ["room_id": String(roomID)],
            referer: "https://live.bilibili.com/\(roomID)"
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
            referer: "https://live.bilibili.com/\(roomID)"
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
            referer: "https://space.bilibili.com/\(uid)"
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard let info = response.payload, info.roomID > 0 else { throw BiliAPIError.missingPayload }
        return info
    }

    func fetchLiveStreamURL(roomID: Int) async throws -> URL {
        var lastError: Error?
        do {
            return try await fetchLegacyLiveStreamURL(roomID: roomID)
        } catch {
            lastError = error
        }

        let attempts: [[String: String]] = [
            [
                "room_id": String(roomID),
                "protocol": "0,1",
                "format": "0,1,2",
                "codec": "0",
                "qn": "10000",
                "platform": "android"
            ],
            [
                "room_id": String(roomID),
                "protocol": "0,1",
                "format": "0,1,2",
                "codec": "0,1",
                "qn": "10000",
                "platform": "web"
            ]
        ]

        for query in attempts {
            do {
                let response: BiliResponse<LivePlayInfoData> = try await get(
                    base: liveURL,
                    path: "/xlive/web-room/v2/index/getRoomPlayInfo",
                    query: query,
                    referer: "https://live.bilibili.com/\(roomID)",
                    userAgent: Self.webUserAgent,
                    cachePolicy: .reloadIgnoringLocalCacheData
                )
                guard response.code == 0 else {
                    throw BiliAPIError.api(code: response.code, message: response.displayMessage)
                }
                if let url = response.payload?.firstPlayableURL {
                    return url
                }
                lastError = BiliAPIError.missingPayload
            } catch {
                lastError = error
            }
        }

        throw lastError ?? BiliAPIError.missingPayload
    }

    private func fetchLegacyLiveStreamURL(roomID: Int) async throws -> URL {
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
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        guard let url = response.payload?.firstURL else {
            throw BiliAPIError.missingPayload
        }
        return url
    }

    func fetchLiveDanmakuHistory(roomID: Int) async throws -> [LiveDanmakuMessage] {
        let response: BiliResponse<LiveDanmakuHistoryData> = try await get(
            base: liveURL,
            path: "/xlive/web-room/v1/dM/gethistory",
            query: ["roomid": String(roomID)],
            referer: "https://live.bilibili.com/\(roomID)"
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        return (response.payload?.room ?? []).filter { !$0.text.isEmpty }
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
            referer: "https://live.bilibili.com"
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        return response.payload?.roomList.filter { $0.roomID > 0 && $0.isLive } ?? []
    }

    private func fetchWBIKeys() async throws -> WBIKeys {
        if let keys = cachedWBIKeys,
           let date = cachedWBIKeysDate,
           Date().timeIntervalSince(date) < 12 * 60 * 60 {
            return keys
        }

        let response: BiliResponse<NavUserInfo> = try await get(
            base: baseURL,
            path: "/x/web-interface/nav",
            query: [:]
        )
        guard let image = response.payload?.wbiImg else {
            if response.code != 0 {
                throw BiliAPIError.api(code: response.code, message: response.displayMessage)
            }
            throw BiliAPIError.missingPayload
        }
        let keys = WBIKeys(
            imgKey: Self.fileStem(from: image.imgURL),
            subKey: Self.fileStem(from: image.subURL)
        )
        cachedWBIKeys = keys
        cachedWBIKeysDate = Date()
        return keys
    }

    private func get<T: Decodable>(
        base: URL,
        path: String,
        query: [String: String],
        referer: String = "https://www.bilibili.com",
        userAgent: String? = nil,
        cookieHeader: String? = nil,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy,
        priority: Float = URLSessionTask.defaultPriority
    ) async throws -> T {
        var request = try makeRequest(
            base: base,
            path: path,
            query: query,
            referer: referer,
            userAgent: userAgent,
            cookieHeader: cookieHeader,
            cachePolicy: cachePolicy
        )
        request.networkServiceType = priority >= URLSessionTask.highPriority ? .responsiveData : .default
        let (data, _) = try await data(for: request, priority: priority)
        guard !data.isEmpty else { throw BiliAPIError.emptyData }
        return try JSONDecoder.bili.decode(T.self, from: data)
    }

    private func postForm<T: Decodable>(
        base: URL,
        path: String,
        body: [String: String],
        referer: String = "https://www.bilibili.com",
        userAgent: String? = nil
    ) async throws -> T {
        var request = try makeRequest(base: base, path: path, query: [:], referer: referer, userAgent: userAgent)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(from: body)
        let (data, _) = try await data(for: request, priority: .userInitiated)
        guard !data.isEmpty else { throw BiliAPIError.emptyData }
        return try JSONDecoder.bili.decode(T.self, from: data)
    }

    private func makeRequest(
        base: URL,
        path: String,
        query: [String: String],
        referer: String = "https://www.bilibili.com",
        userAgent: String? = nil,
        cookieHeader: String? = nil,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
    ) throws -> URLRequest {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw BiliAPIError.invalidURL
        }
        components.path = path
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw BiliAPIError.invalidURL }
        var request = URLRequest(url: url, cachePolicy: cachePolicy)
        applyCommonHeaders(to: &request, referer: referer, userAgent: userAgent, cookieHeader: cookieHeader)
        if cachePolicy != .useProtocolCachePolicy {
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        }
        return request
    }

    private func data(for request: URLRequest, priority: Float = URLSessionTask.defaultPriority) async throws -> (Data, URLResponse) {
        var request = request
        request.networkServiceType = priority >= URLSessionTask.highPriority ? .responsiveData : .default
        return try await session.data(for: request)
    }

    private func requireCSRF() throws -> String {
        guard sessionStore.isLoggedIn else {
            throw BiliAPIError.missingSESSDATA
        }
        guard let csrf = sessionStore.csrfToken(), !csrf.isEmpty else {
            throw BiliAPIError.missingCSRF
        }
        return csrf
    }

    private func applyCommonHeaders(to request: inout URLRequest, referer: String, userAgent: String? = nil, cookieHeader: String? = nil) {
        request.setValue(userAgent ?? Self.mobileUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Origin")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(cookieHeader ?? sessionStore.cookieHeader(), forHTTPHeaderField: "Cookie")
    }

    private var guestModeCookieHeader: String? {
        libraryStore.guestModeEnabled ? sessionStore.anonymousCookieHeader() : nil
    }

    private static func formBody(from fields: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((components.percentEncodedQuery ?? "").utf8)
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
        if let mid = sessionStore.user?.mid, mid > 0 {
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

enum CommentSort: CaseIterable, Identifiable, Hashable {
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
    static var bili: JSONDecoder {
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
