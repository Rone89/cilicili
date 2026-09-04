import Foundation

extension BiliAPIClient {
    func addDynamicComment(
        oid: String,
        type: Int,
        message: String,
        root: Int? = nil,
        parent: Int? = nil
    ) async throws {
        let normalizedOID = oid.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedOID.isEmpty,
              type > 0,
              !normalizedMessage.isEmpty,
              root.map({ $0 > 0 }) ?? true,
              parent.map({ $0 > 0 }) ?? true,
              (root == nil) == (parent == nil)
        else {
            throw BiliAPIError.missingPayload
        }
        let interactionContext = await interactionRequestContext()
        guard interactionContext.isLoggedIn else { throw BiliAPIError.missingSESSDATA }
        guard let csrf = interactionContext.csrfToken, !csrf.isEmpty else {
            throw BiliAPIError.missingCSRF
        }
        var body = [
            "oid": normalizedOID,
            "type": String(type),
            "message": normalizedMessage,
            "plat": "1",
            "csrf": csrf,
        ]
        if let root, let parent {
            body["root"] = String(root)
            body["parent"] = String(parent)
        }
        let response: BiliResponse<EmptyBiliPayload> = try await postForm(
            base: baseURL,
            path: "/x/v2/reply/add",
            body: body,
            referer: "https://t.bilibili.com/",
            cookieHeader: interactionContext.cookieHeader,
            retryPolicy: .api
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
    }

    func setCommentLike(
        oid: String,
        type: Int,
        rpid: Int,
        liked: Bool,
        referer: String = "https://www.bilibili.com"
    ) async throws {
        let normalizedOID = oid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedOID.isEmpty, type > 0, rpid > 0 else {
            throw BiliAPIError.missingPayload
        }
        let context = await interactionRequestContext()
        guard context.isLoggedIn else { throw BiliAPIError.missingSESSDATA }
        guard let csrf = context.csrfToken, !csrf.isEmpty else { throw BiliAPIError.missingCSRF }
        let response: BiliResponse<EmptyBiliPayload> = try await postForm(
            base: baseURL,
            path: "/x/v2/reply/action",
            body: [
                "oid": normalizedOID,
                "type": String(type),
                "rpid": String(rpid),
                "action": liked ? "1" : "0",
                "csrf": csrf,
            ],
            referer: referer,
            cookieHeader: context.cookieHeader,
            retryPolicy: .idempotentMutation
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
    }

    func fetchComments(
        aid: Int,
        cursor: String = "",
        sort: CommentSort = .hot,
        cookieHeader: String? = nil
    ) async throws -> CommentPage {
        try await fetchComments(
            oid: String(aid),
            type: 1,
            cursor: cursor,
            sort: sort,
            cookieHeader: cookieHeader
        )
    }

    func fetchComments(
        oid: String,
        type: Int,
        cursor: String = "",
        sort: CommentSort = .hot,
        cookieHeader: String? = nil
    ) async throws
        -> CommentPage
    {
        let mode = sort == .hot ? "3" : "2"
        let pagination = try Self.commentPaginationString(offset: cursor)
        let resolvedCookieHeader = await resolvedCommentCookieHeader(cookieHeader)
        let response: BiliResponse<CommentPage> = try await get(
            base: baseURL,
            path: "/x/v2/reply/main",
            query: [
                "oid": oid,
                "type": String(type),
                "mode": mode,
                "plat": "1",
                "pagination_str": pagination,
            ],
            cookieHeader: resolvedCookieHeader,
            cachePolicy: .reloadIgnoringLocalCacheData,
            priority: URLSessionTask.defaultPriority
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        return response.payload ?? CommentPage(replies: [], topReplies: [], cursor: nil)
    }

    private static func commentPaginationString(offset: String) throws -> String {
        let data = try JSONEncoder().encode(CommentPaginationRequest(offset: offset))
        return String(decoding: data, as: UTF8.self)
    }

    func fetchCommentReplies(
        aid: Int,
        root: Int,
        page: Int = 1,
        sort: CommentSort? = nil,
        cookieHeader: String? = nil
    ) async throws -> CommentPage {
        try await fetchCommentReplies(
            oid: String(aid),
            type: 1,
            root: root,
            page: page,
            sort: sort,
            cookieHeader: cookieHeader
        )
    }

    func fetchCommentReplies(
        oid: String,
        type: Int,
        root: Int,
        page: Int = 1,
        sort: CommentSort? = nil,
        cookieHeader: String? = nil
    ) async throws -> CommentPage {
        var query = [
            "oid": oid,
            "type": String(type),
            "root": String(root),
            "pn": String(page),
            "ps": "20",
        ]
        if sort == .time {
            query["sort"] = "1"
        }
        let resolvedCookieHeader = await resolvedCommentCookieHeader(cookieHeader)
        let response: BiliResponse<CommentPage> = try await get(
            base: baseURL,
            path: "/x/v2/reply/reply",
            query: query,
            cookieHeader: resolvedCookieHeader,
            cachePolicy: .reloadIgnoringLocalCacheData,
            priority: URLSessionTask.lowPriority
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        return response.payload ?? CommentPage(replies: [], topReplies: [], cursor: nil)
    }

    func fetchCommentDialog(
        aid: Int,
        root: Int,
        dialog: Int,
        size: Int = 20,
        cookieHeader: String? = nil
    ) async throws -> CommentPage {
        try await fetchCommentDialog(
            oid: String(aid),
            type: 1,
            root: root,
            dialog: dialog,
            size: size,
            cookieHeader: cookieHeader
        )
    }

    func fetchCommentDialog(
        oid: String,
        type: Int,
        root: Int,
        dialog: Int,
        size: Int = 20,
        cookieHeader: String? = nil
    ) async throws -> CommentPage
    {
        let resolvedCookieHeader = await resolvedCommentCookieHeader(cookieHeader)
        let response: BiliResponse<CommentPage> = try await get(
            base: baseURL,
            path: "/x/v2/reply/dialog/cursor",
            query: [
                "oid": oid,
                "type": String(type),
                "root": String(root),
                "dialog": String(dialog),
                "size": String(size),
            ],
            cookieHeader: resolvedCookieHeader,
            cachePolicy: .reloadIgnoringLocalCacheData,
            priority: URLSessionTask.lowPriority
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        return response.payload ?? CommentPage(replies: [], topReplies: [], cursor: nil)
    }

    private func resolvedCommentCookieHeader(_ cookieHeader: String?) async -> String {
        if let cookieHeader {
            return cookieHeader
        }
        return await interactionRequestContext().cookieHeader
    }
}

nonisolated enum CommentSort: String, CaseIterable, Identifiable, Hashable {
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

nonisolated private struct CommentPaginationRequest: Encodable {
    let offset: String
}
