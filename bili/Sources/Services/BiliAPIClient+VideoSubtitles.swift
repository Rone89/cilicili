import Foundation

nonisolated struct VideoSubtitleTrack: Decodable, Sendable, Equatable, Identifiable {
    let lan: String
    let lanDoc: String
    let isAI: Bool
    let subtitleURL: String?
    let subtitleURLV2: String?

    var id: String { lan }

    enum CodingKeys: String, CodingKey {
        case lan
        case lanDoc = "lan_doc"
        case type
        case subtitleURL = "subtitle_url"
        case subtitleURLV2 = "subtitle_url_v2"
    }

    init(
        lan: String,
        lanDoc: String? = nil,
        isAI: Bool = false,
        subtitleURL: String? = nil,
        subtitleURLV2: String? = nil
    ) {
        self.lan = lan
        self.lanDoc = lanDoc ?? lan
        self.isAI = isAI
        self.subtitleURL = subtitleURL
        self.subtitleURLV2 = subtitleURLV2
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lan = try container.decode(String.self, forKey: .lan)
        lanDoc = try container.decodeIfPresent(String.self, forKey: .lanDoc) ?? lan
        // type == 1 是 AI 生成字幕轨（type 0 为人工 CC），对齐 PiliPlus 的判定。
        isAI = (try? container.decode(Int.self, forKey: .type)) == 1
        subtitleURL = try container.decodeIfPresent(String.self, forKey: .subtitleURL)
        subtitleURLV2 = try container.decodeIfPresent(String.self, forKey: .subtitleURLV2)
    }
}

nonisolated struct VideoSubtitleCue: Decodable, Sendable, Equatable {
    let from: Double
    let to: Double
    let content: String
}

nonisolated struct VideoSubtitleCueList: Decodable, Sendable, Equatable {
    let body: [VideoSubtitleCue]?
}

nonisolated struct VideoPlayerSubtitleInfo: Decodable, Sendable, Equatable {
    let subtitles: [VideoSubtitleTrack]?
}

nonisolated struct VideoPlayerSubtitlePayload: Decodable, Sendable, Equatable {
    let subtitle: VideoPlayerSubtitleInfo?
}

extension BiliAPIClient {
    /// 播放详情接口的字幕轨列表（含 AI 生成轨）。AI 字幕通常需要登录态，未登录时列表可能为空。
    func fetchVideoSubtitleTracks(aid: Int, cid: Int, bvid: String?) async throws -> [VideoSubtitleTrack] {
        var query = [
            "aid": String(aid),
            "cid": String(cid),
        ]
        if let bvid, !bvid.isEmpty {
            query["bvid"] = bvid
        }
        let signed = try await signedWBIQuery(query)
        let context = await interactionRequestContext()
        let response: BiliResponse<VideoPlayerSubtitlePayload> = try await get(
            base: baseURL,
            path: "/x/player/wbi/v2",
            query: signed,
            cookieHeader: context.cookieHeader
        )
        return response.payload?.subtitle?.subtitles ?? []
    }

    func fetchVideoSubtitleCues(subtitleURL: String) async throws -> [VideoSubtitleCue] {
        // 字幕地址有多种下发形态：`//aisubtitle.hdslb.com/...`（协议相对，最常见）、
        // 完整 http(s)、以及偶见的裸域名。统一规范成 https 绝对地址。
        let secureURL = Self.normalizedSubtitleURL(subtitleURL)
        guard let requestURL = URL(string: secureURL) else {
            throw BiliAPIError.missingPayload
        }
        var request = URLRequest(url: requestURL)
        // 字幕 CDN（如 aisubtitle.hdslb.com）会校验来源；只带 Accept 会被拒绝。
        // 复用 API 头构造，与播放详情请求保持同一 UA/Referer/登录 cookie。
        let context = await interactionRequestContext()
        for (field, value) in BiliURLSessionFactory.apiHeaders(
            referer: "https://www.bilibili.com/",
            userAgent: nil,
            cookieHeader: context.cookieHeader
        ) {
            request.setValue(value, forHTTPHeaderField: field)
        }
        let (data, _) = try await data(
            for: request,
            priority: URLSessionTask.lowPriority,
            retryPolicy: .idempotentMutation
        )
        guard !data.isEmpty else { throw BiliAPIError.emptyData }
        let cues = try JSONDecoder().decode(VideoSubtitleCueList.self, from: data)
        return cues.body ?? []
    }

    /// 对齐 PiliPlus 的 `"https:$subtitleUrl"`：接口多数情况下给协议相对地址。
    static func normalizedSubtitleURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("//") {
            return "https:" + trimmed
        }
        if trimmed.hasPrefix("http://") {
            return "https://" + trimmed.dropFirst("http://".count)
        }
        if trimmed.hasPrefix("https://") {
            return trimmed
        }
        return "https://" + trimmed
    }
}
