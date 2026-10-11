import Foundation

/// PGC media carried by the dynamic API. Its `id`/`aid` are not episode IDs.
nonisolated struct DynamicPGC: Decodable, Hashable, Sendable {
    let title: String
    let cover: String?
    let episodeID: Int?
    let seasonID: Int?
    let jumpURL: URL?
    let badgeText: String?
    let durationText: String?
    let playText: String?
    let danmakuText: String?

    init(from decoder: Decoder) throws {
        let raw = try DynamicJSONValue(from: decoder)
        guard let object = raw.objectValueForDynamicParsing, !object.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Empty PGC media"))
        }
        func text(_ value: DynamicJSONValue?) -> String? {
            let value = value?.textValueForDynamicParsing?.trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value : nil
        }
        func positiveID(_ value: DynamicJSONValue?) -> Int? {
            guard let value = text(value), let id = Int(value), id > 0 else { return nil }
            return id
        }
        title = text(object["title"])?.removingHTMLTags() ?? "番剧更新"
        cover = text(object["cover"])?.normalizedBiliURL()
        let jumpURLString = text(object["jump_url"])?.normalizedBiliURL()
        jumpURL = jumpURLString.flatMap(URL.init(string:)).flatMap { url in
            ["https", "http"].contains(url.scheme?.lowercased() ?? "") && url.host != nil ? url : nil
        }
        episodeID = positiveID(object["epid"]) ?? Self.routeID(in: jumpURL, prefix: "ep")
        seasonID = positiveID(object["season_id"]) ?? Self.routeID(in: jumpURL, prefix: "ss")
        badgeText = text(object["badge"]?.objectValueForDynamicParsing?["text"])
        durationText = text(object["duration_text"])
        let stat = object["stat"]?.objectValueForDynamicParsing
        playText = text(stat?["play"])
        danmakuText = text(stat?["danmaku"])
        guard text(object["title"]) != nil || cover != nil || episodeID != nil || seasonID != nil || jumpURL != nil else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Missing PGC content"))
        }
    }

    var playbackRoute: PgcSeasonRoute? {
        if let episodeID {
            return PgcSeasonRoute(episodeID: episodeID, seasonID: seasonID, title: title, cover: cover)
        }
        return seasonID.map { PgcSeasonRoute(seasonID: $0, title: title, cover: cover) }
    }

    private static func routeID(in url: URL?, prefix: String) -> Int? {
        guard let url, let host = url.host?.lowercased(),
              host == "bilibili.com" || host.hasSuffix(".bilibili.com") else { return nil }
        let parts = url.path.split(separator: "/")
        guard parts.count == 3, parts[0] == "bangumi", parts[1] == "play",
              parts[2].hasPrefix(prefix) else { return nil }
        let digits = parts[2].dropFirst(prefix.count)
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              let id = Int(digits), id > 0 else { return nil }
        return id
    }

    /// Remove the fallback cover thumbnail, while keeping any genuine body images.
    func bodyImages(from images: [DynamicImageItem]) -> [DynamicImageItem] {
        images.filter { image in
            guard let url = image.normalizedURL else { return false }
            return url.biliImageCacheIdentityURLString() != cover?.biliImageCacheIdentityURLString()
        }
    }
}
