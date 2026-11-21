import CoreGraphics
import Foundation

extension BiliAPIClient {
    func fetchArticleDetail(for route: ArticleRoute) async throws -> ArticleDetail {
        switch route.source {
        case .cv(let cvID):
            return try await fetchCVArticleDetail(cvID: cvID, seedRoute: route)
        case .opus(let opusID):
            return try await fetchOpusArticleDetail(opusID: opusID, seedRoute: route)
        case .url(let url):
            switch ArticleRoute.parseSource(from: url) {
            case .cv(let cvID):
                return try await fetchCVArticleDetail(cvID: cvID, seedRoute: route)
            case .opus(let opusID):
                return try await fetchOpusArticleDetail(opusID: opusID, seedRoute: route)
            case .url:
                throw BiliAPIError.api(code: -400, message: "暂不支持原生解析该专栏链接")
            }
        }
    }

    private func fetchCVArticleDetail(cvID: Int, seedRoute: ArticleRoute) async throws -> ArticleDetail {
        let context = await dynamicFeedRequestContext()
        let cookieHeader = Self.uploaderDynamicCookieHeader(
            isLoggedIn: context.isLoggedIn,
            authenticatedCookieHeader: context.cookieHeader,
            anonymousCookieHeader: context.anonymousCookieHeader
        )
        let baseQuery = ["id": String(cvID)]
        let response: BiliResponse<DynamicJSONValue>
        do {
            let signedQuery = try await signedWBIQuery(baseQuery)
            response = try await get(
                base: baseURL,
                path: "/x/article/view",
                query: signedQuery,
                cookieHeader: cookieHeader,
                cachePolicy: .reloadIgnoringLocalCacheData
            )
        } catch {
            response = try await get(
                base: baseURL,
                path: "/x/article/view",
                query: baseQuery,
                cookieHeader: cookieHeader,
                cachePolicy: .reloadIgnoringLocalCacheData
            )
        }

        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        guard let data = response.payload else {
            throw BiliAPIError.missingPayload
        }
        return parseCVArticleDetail(data: data, cvID: cvID, seedRoute: seedRoute)
    }

    private func fetchOpusArticleDetail(opusID: String, seedRoute: ArticleRoute) async throws -> ArticleDetail {
        let context = await dynamicFeedRequestContext()
        let cookieHeader = Self.uploaderDynamicCookieHeader(
            isLoggedIn: context.isLoggedIn,
            authenticatedCookieHeader: context.cookieHeader,
            anonymousCookieHeader: context.anonymousCookieHeader
        )

        do {
            let response: BiliResponse<DynamicJSONValue> = try await get(
                base: baseURL,
                path: "/x/polymer/web-dynamic/v1/opus/detail",
                query: [
                    "id": opusID,
                    "timezone_offset": "-480",
                    "features": "itemOpusStyle,listOnlyfans,opusBigCover,onlyfansVote,decorationCard,onlyfansAssetsV2,forwardListHidden,ugcDelete",
                    "web_location": "333.1330"
                ],
                cookieHeader: cookieHeader,
                cachePolicy: .reloadIgnoringLocalCacheData
            )
            if response.code == 0,
               let itemValue = response.payload?["item"],
               let detail = parseOpusDetailItem(itemValue, opusID: opusID, seedRoute: seedRoute) {
                return detail
            }
            if let fallback = try? await fetchDynamicFallbackDetail(id: opusID, seedRoute: seedRoute) {
                return fallback
            }
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        } catch {
            if let fallback = try? await fetchDynamicFallbackDetail(id: opusID, seedRoute: seedRoute) {
                return fallback
            }
            throw error
        }
    }

    private func fetchDynamicFallbackDetail(id: String, seedRoute: ArticleRoute) async throws -> ArticleDetail {
        let item = try await fetchDynamicDetail(id: id)
        let opus = item.modules?.moduleDynamic?.major?.opus
        let article = item.modules?.moduleDynamic?.major?.article
        let title = opus?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? article?.title
            ?? seedRoute.title
        let summary = article?.summary ?? item.displayText
        let coverURL = (article?.cover ?? opus?.pics?.first?.normalizedURL)
            .flatMap { URL(string: $0) }
            ?? seedRoute.coverURL

        var blocks: [ArticleBlock] = []
        if let text = opus?.displayText ?? item.displayText, !text.isEmpty {
            blocks.append(.paragraph(id: "fallback-text", runs: [ArticleTextRun(text: text)], alignment: .leading))
        }
        if let pics = opus?.pics {
            for (index, pic) in pics.enumerated() {
                if let urlString = pic.normalizedURL, let url = URL(string: urlString) {
                    blocks.append(
                        .image(
                            id: "fallback-pic-\(index)",
                            url: url,
                            caption: nil,
                            width: pic.width.map { CGFloat($0) },
                            height: pic.height.map { CGFloat($0) }
                        )
                    )
                }
            }
        }

        let stats = ArticleStats(
            viewCount: nil,
            likeCount: item.likeCount,
            favoriteCount: nil,
            replyCount: item.replyCount,
            coinCount: nil
        )
        let webURL = seedRoute.webURL
            ?? URL(string: "https://www.bilibili.com/opus/\(opus?.opusID ?? item.id)")
        return ArticleDetail(
            title: title.isEmpty ? "专栏" : title,
            summary: summary,
            coverURL: coverURL,
            authorName: item.author?.name ?? seedRoute.authorName,
            authorMID: item.author?.mid ?? seedRoute.authorMID,
            authorAvatarURL: item.author?.face.map { $0.normalizedBiliURL() }.flatMap(URL.init(string:)) ?? seedRoute.authorAvatarURL,
            publishTime: (item.author?.pubTS ?? 0) > 0 ? item.author?.pubTS : nil,
            categoryName: nil,
            wordCount: nil,
            stats: stats,
            commentOID: item.commentOID ?? seedRoute.commentOID,
            commentType: item.commentType ?? seedRoute.commentType,
            webURL: webURL,
            dynamicID: seedRoute.dynamicID ?? item.idStr,
            cvID: nil,
            isLiked: item.isLiked || seedRoute.initialIsLiked,
            blocks: blocks
        )
    }

    private func parseCVArticleDetail(
        data: DynamicJSONValue,
        cvID: Int,
        seedRoute: ArticleRoute
    ) -> ArticleDetail {
        let title = data["title"]?.textValueForDynamicParsing?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? seedRoute.title
        let summary = data["summary"]?.textValueForDynamicParsing
        let coverString = data["banner_url"]?.textValueForDynamicParsing
            ?? data["image_urls"]?.arrayValue?.first?.textValueForDynamicParsing
            ?? data["origin_image_urls"]?.arrayValue?.first?.textValueForDynamicParsing
        let coverURL = coverString.map { $0.normalizedBiliURL() }.flatMap(URL.init(string:)) ?? seedRoute.coverURL

        let authorObject = data["author"]
        let authorName = authorObject?["name"]?.textValueForDynamicParsing ?? seedRoute.authorName
        let authorMID = authorObject?["mid"]?.intValueForDynamicParsing ?? seedRoute.authorMID
        let authorAvatarURL = authorObject?["face"]?.textValueForDynamicParsing
            .map { $0.normalizedBiliURL() }
            .flatMap(URL.init(string:))
            ?? seedRoute.authorAvatarURL

        let publishTime = data["publish_time"]?.intValueForDynamicParsing
        let categoryName = data["category"]?["name"]?.textValueForDynamicParsing
            ?? data["categories"]?.arrayValue?.first?["name"]?.textValueForDynamicParsing
        let wordCount = data["words"]?.intValueForDynamicParsing

        let statsObject = data["stats"]
        let stats = statsObject.map { statsJSON in
            ArticleStats(
                viewCount: statsJSON["view"]?.intValueForDynamicParsing,
                likeCount: statsJSON["like"]?.intValueForDynamicParsing,
                favoriteCount: statsJSON["favorite"]?.intValueForDynamicParsing,
                replyCount: statsJSON["reply"]?.intValueForDynamicParsing,
                coinCount: statsJSON["coin"]?.intValueForDynamicParsing
            )
        }

        let articleType = data["type"]?.intValueForDynamicParsing ?? 0
        var blocks: [ArticleBlock] = []
        if articleType == 3,
           let opusParagraphs = data["opus"]?["content"]?["paragraphs"]?.arrayValue,
           !opusParagraphs.isEmpty {
            blocks = ArticleContentParser.parseOpusParagraphs(opusParagraphs)
        }
        if blocks.isEmpty, let htmlContent = data["content"]?.textValueForDynamicParsing {
            blocks = ArticleContentParser.parseHTML(htmlContent)
        }
        if blocks.isEmpty, let summary, !summary.isEmpty {
            blocks = [.paragraph(id: "cv-summary", runs: [ArticleTextRun(text: summary)], alignment: .leading)]
        }

        let commentOID = seedRoute.commentOID ?? String(cvID)
        let commentType = seedRoute.commentType ?? 12
        let webURL = seedRoute.webURL ?? URL(string: "https://www.bilibili.com/read/cv\(cvID)")
        let dynamicID = data["dyn_id_str"]?.textValueForDynamicParsing ?? seedRoute.dynamicID
        let isLiked = (data["like"]?.intValueForDynamicParsing == 1) || seedRoute.initialIsLiked

        return ArticleDetail(
            title: title.isEmpty ? "专栏" : title,
            summary: summary,
            coverURL: coverURL,
            authorName: authorName,
            authorMID: authorMID,
            authorAvatarURL: authorAvatarURL,
            publishTime: publishTime,
            categoryName: categoryName,
            wordCount: wordCount,
            stats: stats,
            commentOID: commentOID,
            commentType: commentType,
            webURL: webURL,
            dynamicID: dynamicID,
            cvID: cvID,
            isLiked: isLiked,
            blocks: blocks
        )
    }

    private func parseOpusDetailItem(
        _ item: DynamicJSONValue,
        opusID: String,
        seedRoute: ArticleRoute
    ) -> ArticleDetail? {
        let modules = item["modules"]?.arrayValue ?? []
        var title = seedRoute.title
        var coverURL = seedRoute.coverURL
        var authorName = seedRoute.authorName
        var authorMID = seedRoute.authorMID
        var authorAvatarURL = seedRoute.authorAvatarURL
        var publishTime: Int?
        var blocks: [ArticleBlock] = []
        var likeCount: Int?
        var favoriteCount: Int?
        var replyCount: Int?
        var coinCount: Int?

        for module in modules {
            let moduleType = module["module_type"]?.stringValue ?? ""
            switch moduleType {
            case "MODULE_TYPE_TITLE":
                if let text = module["module_title"]?["text"]?.textValueForDynamicParsing,
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    title = text
                }
            case "MODULE_TYPE_TOP":
                if let firstPic = module["module_top"]?["display"]?["album"]?["pics"]?.arrayValue?.first,
                   let picURL = firstPic["url"]?.textValueForDynamicParsing.map({ $0.normalizedBiliURL() }),
                   let url = URL(string: picURL) {
                    coverURL = url
                }
            case "MODULE_TYPE_AUTHOR":
                let author = module["module_author"]
                authorName = author?["name"]?.textValueForDynamicParsing ?? authorName
                authorMID = author?["mid"]?.intValueForDynamicParsing ?? authorMID
                if let face = author?["face"]?.textValueForDynamicParsing.map({ $0.normalizedBiliURL() }),
                   let faceURL = URL(string: face) {
                    authorAvatarURL = faceURL
                }
                publishTime = author?["pub_ts"]?.intValueForDynamicParsing ?? publishTime
            case "MODULE_TYPE_CONTENT":
                if let rawParagraphs = module["module_content"]?["paragraphs"]?.arrayValue {
                    blocks = ArticleContentParser.parseOpusParagraphs(rawParagraphs)
                }
            case "MODULE_TYPE_STAT":
                let stat = module["module_stat"]
                likeCount = stat?["like"]?["count"]?.intValueForDynamicParsing ?? likeCount
                favoriteCount = stat?["favorite"]?["count"]?.intValueForDynamicParsing ?? favoriteCount
                replyCount = stat?["comment"]?["count"]?.intValueForDynamicParsing ?? replyCount
                coinCount = stat?["coin"]?["count"]?.intValueForDynamicParsing ?? coinCount
            default:
                break
            }
        }

        if blocks.isEmpty, title == "专栏", authorName == nil {
            return nil
        }

        let basic = item["basic"]
        let commentOID = basic?["comment_id_str"]?.textValueForDynamicParsing ?? seedRoute.commentOID ?? opusID
        let commentType = basic?["comment_type"]?.intValueForDynamicParsing ?? seedRoute.commentType ?? 11
        let isLiked = (basic?["like_status"]?.intValueForDynamicParsing == 1) || seedRoute.initialIsLiked
        let stats = ArticleStats(
            viewCount: nil,
            likeCount: likeCount,
            favoriteCount: favoriteCount,
            replyCount: replyCount,
            coinCount: coinCount
        )
        let webURL = seedRoute.webURL ?? URL(string: "https://www.bilibili.com/opus/\(opusID)")

        return ArticleDetail(
            title: title.isEmpty ? "专栏" : title,
            summary: nil,
            coverURL: coverURL,
            authorName: authorName,
            authorMID: authorMID,
            authorAvatarURL: authorAvatarURL,
            publishTime: publishTime,
            categoryName: nil,
            wordCount: nil,
            stats: stats,
            commentOID: commentOID,
            commentType: commentType,
            webURL: webURL,
            dynamicID: seedRoute.dynamicID ?? opusID,
            cvID: nil,
            isLiked: isLiked,
            blocks: blocks
        )
    }

    func setArticleLike(cvID: Int, liked: Bool) async throws {
        guard cvID > 0 else { throw BiliAPIError.missingPayload }
        let context = try await requireInteractionCSRFContext()
        let body = [
            "id": String(cvID),
            "type": liked ? "1" : "2",
            "csrf": context.csrf
        ]
        let response: BiliResponse<DynamicJSONValue> = try await postForm(
            base: baseURL,
            path: "/x/article/like",
            body: body,
            referer: "https://www.bilibili.com/read/cv\(cvID)",
            cookieHeader: context.context.cookieHeader
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
    }
}

private extension DynamicJSONValue {
    subscript(key: String) -> DynamicJSONValue? {
        objectValueForDynamicParsing?[key]
    }

    var arrayValue: [DynamicJSONValue]? {
        if case .array(let array) = self {
            return array
        }
        return nil
    }

    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }
}
