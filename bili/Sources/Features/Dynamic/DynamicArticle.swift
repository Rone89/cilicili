import Foundation

nonisolated struct DynamicArticle: Hashable {
    let title: String
    let summary: String?
    let cover: String?
    let url: URL?

    init?(raw: DynamicJSONValue?) {
        guard let object = raw?.objectValueForDynamicParsing, !object.isEmpty else { return nil }
        title = object["title"]?.textValueForDynamicParsing ?? "专栏"
        summary = object["desc"]?.textValueForDynamicParsing
        let covers: [DynamicJSONValue]
        if case .array(let values) = object["covers"] { covers = values } else { covers = [] }
        cover = (object["cover"]?.textValueForDynamicParsing
            ?? covers.first?.textValueForDynamicParsing
            ?? object["covers"]?.dynamicImageItems.first?.normalizedURL)?.normalizedBiliURL()
        if let rawURL = object["jump_url"]?.textValueForDynamicParsing, let normalizedURL = Self.normalizedURL(rawURL) {
            url = normalizedURL
        } else if let id = object["id"]?.intValueForDynamicParsing, id > 0 {
            url = URL(string: "https://www.bilibili.com/read/cv\(id)")
        } else {
            url = nil
        }
    }

    init(opus: DynamicOpus, dynamicID: String) {
        title = opus.title ?? "专栏"
        summary = opus.displayText
        cover = opus.pics?.first?.normalizedURL
        url = opus.jumpURL.flatMap(Self.normalizedURL)
            ?? URL(string: "https://www.bilibili.com/opus/\(opus.opusID ?? dynamicID)")
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
