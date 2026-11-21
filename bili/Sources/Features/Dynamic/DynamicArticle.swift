import Foundation

nonisolated struct DynamicArticle: Hashable {
    let title: String
    let summary: String?
    let cover: String?
    let url: URL?
    let articleID: Int?
    let opusID: String?

    init?(raw: DynamicJSONValue?) {
        guard let object = raw?.objectValueForDynamicParsing, !object.isEmpty else { return nil }
        title = object["title"]?.textValueForDynamicParsing ?? "专栏"
        summary = object["desc"]?.textValueForDynamicParsing
        let covers: [DynamicJSONValue]
        if case .array(let values) = object["covers"] { covers = values } else { covers = [] }
        cover = (object["cover"]?.textValueForDynamicParsing
            ?? covers.first?.textValueForDynamicParsing
            ?? object["covers"]?.dynamicImageItems.first?.normalizedURL)?.normalizedBiliURL()
        let parsedID = object["id"]?.intValueForDynamicParsing
        articleID = (parsedID ?? 0) > 0 ? parsedID : nil
        opusID = nil
        if let rawURL = object["jump_url"]?.textValueForDynamicParsing, let normalizedURL = Self.normalizedURL(rawURL) {
            url = normalizedURL
        } else if let id = parsedID, id > 0 {
            url = URL(string: "https://www.bilibili.com/read/cv\(id)")
        } else {
            url = nil
        }
    }

    init(opus: DynamicOpus, dynamicID: String) {
        title = opus.title ?? "专栏"
        summary = opus.displayText
        cover = opus.pics?.first?.normalizedURL
        articleID = nil
        let resolvedOpusID = opus.opusID?.trimmingCharacters(in: .whitespacesAndNewlines)
        opusID = (resolvedOpusID?.isEmpty == false ? resolvedOpusID : nil) ?? dynamicID
        url = opus.jumpURL.flatMap(Self.normalizedURL)
            ?? URL(string: "https://www.bilibili.com/opus/\(opus.opusID ?? dynamicID)")
    }

    func route(from item: DynamicFeedItem? = nil) -> ArticleRoute? {
        let source: ArticleRoute.Source
        if let articleID, articleID > 0 {
            source = .cv(id: articleID)
        } else if let url {
            let parsed = ArticleRoute.parseSource(from: url)
            if case .url = parsed, let opusID, !opusID.isEmpty {
                source = .opus(id: opusID)
            } else {
                source = parsed
            }
        } else if let opusID, !opusID.isEmpty {
            source = .opus(id: opusID)
        } else if let item, !item.id.isEmpty {
            source = .opus(id: item.id)
        } else {
            return nil
        }

        let coverURL = cover.flatMap(URL.init(string:))
        let avatarURL = item?.author?.face.map { $0.normalizedBiliURL() }.flatMap(URL.init(string:))
        return ArticleRoute(
            source: source,
            title: title,
            coverURL: coverURL,
            authorName: item?.author?.name,
            authorMID: item?.author?.mid,
            authorAvatarURL: avatarURL,
            commentOID: item?.commentOID,
            commentType: item?.commentType,
            webURL: url,
            dynamicID: item?.idStr,
            initialIsLiked: item?.isLiked ?? false,
            initialLikeCount: item?.likeCount
        )
    }

    private static func normalizedURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw.hasPrefix("//") ? "https:" + raw : raw),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
        return url
    }
}

extension DynamicFeedItem {
    var article: DynamicArticle? {
        if let article = modules?.moduleDynamic?.major?.article { return article }
        guard type == "DYNAMIC_TYPE_ARTICLE" else { return nil }
        return opusArticle
    }

    var opusArticle: DynamicArticle? {
        modules?.moduleDynamic?.major?.opus.map { DynamicArticle(opus: $0, dynamicID: idStr) }
    }
}
