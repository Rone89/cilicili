import CoreGraphics
import Foundation

nonisolated struct ArticleRoute: Identifiable, Hashable, Sendable {
    enum Source: Hashable, Sendable {
        case cv(id: Int)
        case opus(id: String)
        case url(URL)
    }

    let source: Source
    let title: String
    let coverURL: URL?
    let authorName: String?
    let authorMID: Int?
    let authorAvatarURL: URL?
    let commentOID: String?
    let commentType: Int?
    let webURL: URL?
    let dynamicID: String?
    let initialIsLiked: Bool
    let initialLikeCount: Int?

    init(
        source: Source,
        title: String,
        coverURL: URL? = nil,
        authorName: String? = nil,
        authorMID: Int? = nil,
        authorAvatarURL: URL? = nil,
        commentOID: String? = nil,
        commentType: Int? = nil,
        webURL: URL? = nil,
        dynamicID: String? = nil,
        initialIsLiked: Bool = false,
        initialLikeCount: Int? = nil
    ) {
        self.source = source
        self.title = title
        self.coverURL = coverURL
        self.authorName = authorName
        self.authorMID = authorMID
        self.authorAvatarURL = authorAvatarURL
        self.commentOID = commentOID
        self.commentType = commentType
        self.webURL = webURL
        self.dynamicID = dynamicID
        self.initialIsLiked = initialIsLiked
        self.initialLikeCount = initialLikeCount
    }

    var id: String {
        switch source {
        case .cv(let id):
            return "cv:\(id)"
        case .opus(let id):
            return "opus:\(id)"
        case .url(let url):
            return "url:\(url.absoluteString)"
        }
    }

    var supportsNativeReader: Bool {
        switch source {
        case .cv, .opus:
            return true
        case .url(let url):
            if case .url = Self.parseSource(from: url) {
                return false
            }
            return true
        }
    }

    var canonicalWebURL: URL? {
        if let webURL {
            return webURL
        }
        switch source {
        case .cv(let id):
            return URL(string: "https://www.bilibili.com/read/cv\(id)")
        case .opus(let id):
            return URL(string: "https://www.bilibili.com/opus/\(id)")
        case .url(let url):
            return url
        }
    }

    static func parseSource(from url: URL) -> Source {
        let absolute = url.absoluteString
        if let cvID = extractInteger(pattern: #"/read/(?:mobile/)?cv(\d+)"#, in: absolute), cvID > 0 {
            return .cv(id: cvID)
        }
        if let opusID = extractMatch(pattern: #"/opus/(\d+)"#, in: absolute), !opusID.isEmpty {
            return .opus(id: opusID)
        }
        return .url(url)
    }

    private static func extractInteger(pattern: String, in text: String) -> Int? {
        guard let value = extractMatch(pattern: pattern, in: text) else { return nil }
        return Int(value)
    }

    private static func extractMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[captureRange])
    }
}

nonisolated enum ArticleTextAlignment: Hashable, Sendable {
    case leading
    case center
    case trailing
}

nonisolated struct ArticleTextRun: Hashable, Sendable {
    let text: String
    let isBold: Bool
    let isItalic: Bool
    let isStrikethrough: Bool
    let isCode: Bool
    let linkURL: URL?

    init(
        text: String,
        isBold: Bool = false,
        isItalic: Bool = false,
        isStrikethrough: Bool = false,
        isCode: Bool = false,
        linkURL: URL? = nil
    ) {
        self.text = text
        self.isBold = isBold
        self.isItalic = isItalic
        self.isStrikethrough = isStrikethrough
        self.isCode = isCode
        self.linkURL = linkURL
    }
}

nonisolated enum ArticleBlock: Identifiable, Hashable, Sendable {
    case heading(id: String, level: Int, text: String)
    case paragraph(id: String, runs: [ArticleTextRun], alignment: ArticleTextAlignment)
    case blockquote(id: String, runs: [ArticleTextRun])
    case list(id: String, ordered: Bool, items: [[ArticleTextRun]])
    case code(id: String, language: String?, text: String)
    case image(id: String, url: URL, caption: String?, width: CGFloat?, height: CGFloat?)
    case divider(id: String)
    case linkCard(id: String, title: String, subtitle: String?, coverURL: URL?, url: URL?)

    var id: String {
        switch self {
        case .heading(let id, _, _),
             .paragraph(let id, _, _),
             .blockquote(let id, _),
             .list(let id, _, _),
             .code(let id, _, _),
             .image(let id, _, _, _, _),
             .divider(let id),
             .linkCard(let id, _, _, _, _):
            return id
        }
    }
}

nonisolated struct ArticleStats: Hashable, Sendable {
    let viewCount: Int?
    let likeCount: Int?
    let favoriteCount: Int?
    let replyCount: Int?
    let coinCount: Int?
}

nonisolated struct ArticleDetail: Hashable, Sendable {
    let title: String
    let summary: String?
    let coverURL: URL?
    let authorName: String?
    let authorMID: Int?
    let authorAvatarURL: URL?
    let publishTime: Int?
    let categoryName: String?
    let wordCount: Int?
    let stats: ArticleStats?
    let commentOID: String?
    let commentType: Int?
    let webURL: URL?
    let dynamicID: String?
    let cvID: Int?
    let isLiked: Bool
    let blocks: [ArticleBlock]

    var imageURLs: [URL] {
        var urls: [URL] = []
        if let coverURL {
            urls.append(coverURL)
        }
        for block in blocks {
            if case .image(_, let url, _, _, _) = block, !urls.contains(url) {
                urls.append(url)
            }
        }
        return urls
    }
}
